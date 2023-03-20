// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "../src/timelock/Timelock.sol";
import "./mocks/MockERC20.sol";

contract TimelockTest is Test {
    function test_execute() external {
        address admin = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
        address alice = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
        MockERC20 target = new MockERC20("TA", "Token A", 18);
        target.mintTo(1 ether, alice);

        LevelTimelock lock = new LevelTimelock(admin, 24 hours);
        vm.warp(20);
        string memory sig = "mintTo(uint256,address)";
        bytes memory data = abi.encode(10 ether, alice);

        vm.startPrank(admin);
        vm.expectRevert();
        lock.queueTransaction(address(target), 0, sig, data, 21);

        uint256 eta = 20 + 24 hours;
        lock.queueTransaction(address(target), 0, sig, data, eta);

        vm.warp(20 + 24 hours - 1);
        vm.expectRevert();
        lock.executeTransaction(address(target), 0, sig, data, eta);

        vm.warp(20 + 24 hours);
        lock.executeTransaction(address(target), 0, sig, data, eta);

        assertEq(target.balanceOf(alice), 11 ether);
    }
}
