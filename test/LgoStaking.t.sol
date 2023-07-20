    // SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "../src/farm/LgoStaking.sol";
import "./mocks/MockERC20.sol";
import "../src/fund/LlpRewardDistributor.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import {MockPool} from "./mocks/MockPool.sol";

contract LevelStakeTest is Test {
    address owner;
    MockERC20 lgo;
    MockERC20 rewardToken;
    LlpRewardDistributor llgpRewardDistributor;
    LgoStaking lgoStaking;

    constructor() {
        owner = msg.sender;
        vm.startPrank(owner);
        lgo = new MockERC20("LGO Token", "LGO", 18);
        rewardToken = new MockERC20("LLP Token", "LLP", 18);
        llgpRewardDistributor = new LlpRewardDistributor();
        lgoStaking = new LgoStaking();
        WETH9 weth = new WETH9();
        ETHUnwrapper ethUnwrapper = new ETHUnwrapper(address(weth));
        llgpRewardDistributor.initialize(
            address(new MockPool()), address(rewardToken), address(weth), address(ethUnwrapper)
        );
        llgpRewardDistributor.setRequester(address(lgoStaking));
        lgoStaking.initialize(address(lgo), address(llgpRewardDistributor));
        rewardToken.mintTo(1_000_000_000 ether, address(llgpRewardDistributor));
        llgpRewardDistributor.setController(msg.sender);
        llgpRewardDistributor.setRewardsPerSecond(1 ether);
        console.log(lgoStaking.getRewardToken());
        vm.stopPrank();
    }

    function testSetRewardPerSecond() external {
        vm.startPrank(owner);
        llgpRewardDistributor.setRewardsPerSecond(5 ether);
        assertEq(llgpRewardDistributor.rewardsPerSecond(), 5 ether);
        vm.stopPrank();
    }

    function testStake() external {
        uint256 _amount = 1e18;
        vm.warp(10);
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        vm.startPrank(_user1);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user1, _amount);
        assertEq(lgo.balanceOf(address(lgoStaking)), _amount);
        (uint256 _total, int256 _debt) = lgoStaking.userInfo(_user1);
        assertEq(_total, _amount);
        assertEq(_debt, 0);
        vm.stopPrank();
        //
        vm.warp(20);
        address _user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
        vm.startPrank(_user2);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user2, _amount);
        assertEq(lgo.balanceOf(address(lgoStaking)), 2e18);
        (_total, _debt) = lgoStaking.userInfo(_user2);
        assertEq(_total, _amount);
        assertEq(_debt, 10e18);
        (_total, _debt) = lgoStaking.userInfo(_user1);
        assertEq(_total, _amount);
        assertEq(_debt, 0);
        vm.stopPrank();
    }

    function testGetPendingRewards() external {
        uint256 _amount = 1e18;
        vm.warp(10);
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        vm.startPrank(_user1);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user1, _amount);
        uint256 _rewards = lgoStaking.pendingRewards(_user1);
        assertEq(_rewards, 0);
        vm.stopPrank();
        //
        vm.warp(20);
        _rewards = lgoStaking.pendingRewards(_user1);
        assertEq(_rewards, 10 ether);
        // user 2: stake
        address _user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
        vm.startPrank(_user2);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user2, _amount);
        vm.stopPrank();

        //Get pending reward
        _rewards = lgoStaking.pendingRewards(_user1);
        assertEq(_rewards, 10 ether);

        vm.warp(25);
        _rewards = lgoStaking.pendingRewards(_user1);
        assertEq(_rewards, 12.5 ether);

        uint256 _rewardsU2 = lgoStaking.pendingRewards(_user2);
        assertEq(_rewardsU2, 2.5 ether);
        //user 2: deposit more
        vm.warp(31);

        _rewardsU2 = lgoStaking.pendingRewards(_user2);
        assertEq(_rewardsU2, 5.5 ether);
        //
        vm.startPrank(_user2);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user2, _amount);

        vm.warp(37);

        (uint256 _total,) = lgoStaking.userInfo(_user2);
        assertEq(_total, 2 ether);
        _rewards = lgoStaking.pendingRewards(_user1);
        assertEq(_rewards, 17.5 ether);
        //
        _rewardsU2 = lgoStaking.pendingRewards(_user2);

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
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user1, _amount);
        // Unstake
        vm.warp(10);
        lgoStaking.unstake(_user1, _amount);
        assertEq(lgo.balanceOf(_user1), _amount);
        // claims
        lgoStaking.claimRewards(_user1);
        assertEq(rewardToken.balanceOf(_user1), 9 ether);

        vm.warp(30);
        assertEq(lgoStaking.pendingRewards(_user1), 0);
        vm.stopPrank();
    }

    function testClaim() external {
        vm.warp(1);
        // Staking
        address _user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
        uint256 _amount = 1e18;
        vm.startPrank(_user1);
        lgo.mint(_amount);
        lgo.approve(address(lgoStaking), _amount);
        lgoStaking.stake(_user1, _amount);
        // Claim
        vm.warp(10);
        lgoStaking.claimRewards(_user1);
        assertEq(rewardToken.balanceOf(_user1), 9 ether);
        vm.warp(20);
        assertEq(rewardToken.balanceOf(_user1), 9 ether);
        vm.stopPrank();
    }
}
