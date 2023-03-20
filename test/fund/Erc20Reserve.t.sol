pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {MockERC20} from "./../mocks/MockERC20.sol";
import "src/fund/Erc20Reserve.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract Erc20ReserveTest is Test {
    address owner;
    address user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));

    function test_transfer() external {
        owner = msg.sender;
        Erc20Reserve reserve = new Erc20Reserve();
        MockERC20 lvl = new MockERC20("LVL", "LVL", 18);
        lvl.mintTo(1000e18, address(reserve));

        // token = 0x0 => revert
        vm.expectRevert();
        reserve.transfer(IERC20(address(0)), owner, 10e18);

        // reciver = 0x0 => revert
        vm.expectRevert();
        reserve.transfer(IERC20(lvl), address(0), 10e18);

        // amount = 0 => revert
        vm.expectRevert();
        reserve.transfer(IERC20(lvl), owner, 0);

        // success
        reserve.transfer(IERC20(lvl), owner, 10e18);
    }
}
