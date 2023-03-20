    // SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "src/farm/LevelZap.sol";
import "../mocks/MockERC20.sol";
import {WETH9} from "../mocks/WETH.sol";
import {ETHUnwrapper} from "../mocks/ETHUnwrapper.sol";
import {MockUniswapV2Router02} from "../mocks/MockUniswapV2Router02.sol";
import {MockLevelMaster} from "../mocks/MockLevelMaster.sol";
import {MockUniswapPair} from "../mocks/MockUniswapPair.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

contract LevelZapTest is Test {
    address owner;
    IWETH public weth;
    LevelZap public zap;
    MockLevelMaster levelMaster;
    MockUniswapV2Router02 swapRouter;
    MockERC20 lvl;
    MockUniswapPair lvlWbnb;
    address user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
    address user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));

    function setUp() external {
        owner = msg.sender;
        vm.startPrank(owner);
        lvl = new MockERC20("LVL", "LVL", 18);
        weth = IWETH(address(new WETH9()));
        lvlWbnb = new MockUniswapPair(address(weth), address(lvl));
        levelMaster = new MockLevelMaster();
        levelMaster.addPool(address(lvlWbnb));

        swapRouter = new MockUniswapV2Router02(address(weth), address(lvl));
        zap = new LevelZap(address(levelMaster), address(swapRouter), address(weth));
        lvl.mintTo(1000e18, address(swapRouter));
        lvl.mintTo(1000e18, address(zap));
        lvlWbnb.mintTo(1000e18, address(zap));
        vm.deal(address(zap), 1000 ether);
        vm.stopPrank();
    }

    function test_add_zap() external {
        vm.expectRevert();
        zap.addZap(address(lvl), 0);

        vm.startPrank(owner);
        // token = 0x0 => revert
        vm.expectRevert();
        zap.addZap(address(0), 0);

        // success
        zap.addZap(address(lvl), 0);
    }

    function test_remove_zap() external {
        vm.startPrank(owner);
        // success
        zap.addZap(address(lvl), 0);
        vm.stopPrank();

        //not owner => revert
        vm.expectRevert();
        zap.removeZap(0);

        vm.startPrank(owner);
        // id not found => revert
        vm.expectRevert();
        zap.removeZap(1);

        // success
        zap.removeZap(0);
        vm.stopPrank();
    }

    function test_zap() external {
        vm.startPrank(owner);
        zap.addZap(address(lvl), 0);
        zap.addZap(address(lvl), 1);
        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.startPrank(user1);

        // Pool not have LP => revert
        vm.expectRevert();
        zap.zap{value: 50 ether}(1, 0, true);

        // zap success
        zap.zap{value: 50 ether}(0, 1e18, true);
        vm.stopPrank();

        vm.prank(owner);
        zap.removeZap(0);

        vm.startPrank(user1);

        // inactive => revert
        vm.expectRevert();
        zap.zap{value: 50 ether}(0, 1e18, true);
        vm.stopPrank();
    }
}
