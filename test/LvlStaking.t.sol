    // SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/farm/LvlStaking.sol";
import "./mocks/MockERC20.sol";
import "../src/fund/LlpRewardDistributor.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import {MockPool} from "./mocks/MockPool.sol";

contract LvlStakingTest is Test {
    address owner = 0xCE2ee0D3666342d263F534e9375c1A450AC7624d;
    MockERC20 LVL;
    MockERC20 LLP;
    WETH9 WETH;

    ETHUnwrapper ethUnwrapper;
    LvlStaking lvlStaking;

    MockPool pool;

    constructor() {
        vm.startPrank(owner);
        LVL = new MockERC20("LVL Token", "LVL", 18);
        LLP = new MockERC20("LLP Token", "LLP", 18);
        WETH9 weth = new WETH9();

        ethUnwrapper = new ETHUnwrapper(address(weth));
        pool = new MockPool();

        address proxyAdmin = address(bytes20("proxy-admin"));
        LvlStaking impl = new LvlStaking();
        Proxy proxy = new Proxy(address(impl), proxyAdmin, new bytes(0));
        lvlStaking = LvlStaking(address(proxy));

        lvlStaking.initialize(address(pool), address(LVL), address(LLP), address(weth), address(ethUnwrapper));

        LLP.mintTo(1_000_000_000 ether, address(lvlStaking));
        lvlStaking.setController(owner);
        lvlStaking.setRewardsPerSecond(1 ether);
        vm.stopPrank();
    }

    function testSetRewardPerSecond() external {
        vm.startPrank(owner);
        lvlStaking.setRewardsPerSecond(5 ether);
        assertEq(lvlStaking.rewardsPerSecond(), 5 ether);
        vm.stopPrank();
    }

    function testStake() external {
        uint256 _amount = 1e18;
        vm.warp(10);
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        vm.startPrank(_user1);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user1, _amount);
        assertEq(LVL.balanceOf(address(lvlStaking)), _amount);
        (uint256 _total, int256 _debt) = lvlStaking.userInfo(_user1);
        assertEq(_total, _amount);
        assertEq(_debt, 0);
        vm.stopPrank();
        //
        vm.warp(20);
        address _user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
        vm.startPrank(_user2);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user2, _amount);
        assertEq(LVL.balanceOf(address(lvlStaking)), 2e18);
        (_total, _debt) = lvlStaking.userInfo(_user2);
        assertEq(_total, _amount);
        assertEq(_debt, 10e18);
        (_total, _debt) = lvlStaking.userInfo(_user1);
        assertEq(_total, _amount);
        assertEq(_debt, 0);
        vm.stopPrank();
    }

    function testGetPendingRewards() external {
        uint256 _amount = 1e18;
        vm.warp(10);
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        vm.startPrank(_user1);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user1, _amount);
        uint256 _rewards = lvlStaking.pendingRewards(_user1);
        assertEq(_rewards, 0);
        vm.stopPrank();
        //
        vm.warp(20);
        _rewards = lvlStaking.pendingRewards(_user1);
        assertEq(_rewards, 10 ether);
        // user 2: stake
        address _user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
        vm.startPrank(_user2);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user2, _amount);
        vm.stopPrank();

        //Get pending reward
        _rewards = lvlStaking.pendingRewards(_user1);
        assertEq(_rewards, 10 ether);

        vm.warp(25);
        _rewards = lvlStaking.pendingRewards(_user1);
        assertEq(_rewards, 12.5 ether);

        uint256 _rewardsU2 = lvlStaking.pendingRewards(_user2);
        assertEq(_rewardsU2, 2.5 ether);
        //user 2: deposit more
        vm.warp(31);

        _rewardsU2 = lvlStaking.pendingRewards(_user2);
        assertEq(_rewardsU2, 5.5 ether);
        //
        vm.startPrank(_user2);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user2, _amount);

        vm.warp(37);

        (uint256 _total,) = lvlStaking.userInfo(_user2);
        assertEq(_total, 2 ether);
        _rewards = lvlStaking.pendingRewards(_user1);
        assertEq(_rewards, 17.5 ether);
        //
        _rewardsU2 = lvlStaking.pendingRewards(_user2);

        assertEq(_rewardsU2, 9.5 ether);
        assertEq(_rewardsU2 + _rewards, 27 ether);
        vm.stopPrank();
    }

    function testUnstake() external {
        vm.warp(1);
        // Staking
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        uint256 _amount = 1e18;
        vm.startPrank(_user1);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user1, _amount);
        // Unstake
        vm.warp(10);
        lvlStaking.unstake(_user1, _amount);
        assertEq(LVL.balanceOf(_user1), _amount);
        // claims
        lvlStaking.claimRewards(_user1);
        assertEq(LLP.balanceOf(_user1), 9 ether);

        vm.warp(30);
        assertEq(lvlStaking.pendingRewards(_user1), 0);
        vm.stopPrank();
    }

    function testClaim() external {
        vm.warp(1);
        // Staking
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        uint256 _amount = 1e18;
        vm.startPrank(_user1);
        LVL.mint(_amount);
        LVL.approve(address(lvlStaking), _amount);
        lvlStaking.stake(_user1, _amount);
        // Claim
        vm.warp(10);
        lvlStaking.claimRewards(_user1);
        assertEq(LLP.balanceOf(_user1), 9 ether);
        vm.warp(20);
        assertEq(LLP.balanceOf(_user1), 9 ether);
        vm.stopPrank();
    }
}
