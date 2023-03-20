    // SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "src/farm/LevelMasterV2.sol";
import "src/farm/LevelStake.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockPool.sol";
import "src/interfaces/IRewarder.sol";
import {WETH9} from "../mocks/WETH.sol";
import {ETHUnwrapper} from "../mocks/ETHUnwrapper.sol";
import {MockRewarder} from "../mocks/MockRewarder.sol";
import {MockLevelStake} from "../mocks/MockLevelStake.sol";

contract LevelMaster2Test is Test {
    address owner;
    MockERC20 stakeToken;
    MockERC20 rewardToken;
    MockERC20 btc;
    LevelMasterV2 levelMaster;
    MockPool public pool;
    MockLevelStake public levelStake;
    IWETH public weth;
    IRewarder rewarder;
    address user1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
    address user2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
    address user3 = vm.addr(uint256(keccak256(abi.encodePacked("3"))));
    address user4 = vm.addr(uint256(keccak256(abi.encodePacked("4"))));

    function setUp() external {
        owner = msg.sender;
        vm.startPrank(owner);
        rewarder = IRewarder(address(new MockRewarder()));
        stakeToken = new MockERC20("Stake Token", "stToken", 18);
        rewardToken = new MockERC20("Reward Token", "rwToken", 18);
        btc = new MockERC20("BTC", "BTC", 18);
        pool = new MockPool();
        pool.setLpToken(address(stakeToken));
        weth = IWETH(address(new WETH9()));
        levelStake = new MockLevelStake(address(rewardToken));
        levelMaster = new LevelMasterV2(address(pool), address(levelStake), address(weth), address(rewardToken));
        vm.stopPrank();
    }

    function test_get_pool_length() external {
        vm.startPrank(owner);
        levelMaster.add(100, stakeToken, true, IRewarder(address(0)));
        levelMaster.add(100, new MockERC20("Stake Token 2", "stToken", 18), true, rewarder);
        vm.stopPrank();
        assertEq(levelMaster.poolLength(), 2);
    }

    function test_add_lp() external {
        vm.startPrank(owner);
        levelMaster.add(100, stakeToken, true, IRewarder(address(0)));
        vm.expectRevert();
        levelMaster.add(1e7, stakeToken, true, IRewarder(address(0)));
        vm.expectRevert();
        levelMaster.add(100, stakeToken, true, IRewarder(address(0)));
        vm.stopPrank();
    }

    function test_update_rewarder() external {
        vm.startPrank(owner);
        levelMaster.add(100, stakeToken, true, IRewarder(address(0)));
        levelMaster.set(0, 1000, true, IRewarder(address(0)), true);
        vm.expectRevert();
        levelMaster.set(0, 1e7, true, IRewarder(address(0)), true);
        vm.stopPrank();
    }

    function test_set_reward_per_second() external {
        vm.startPrank(owner);
        levelMaster.setRewardPerSecond(10 ether);
        vm.expectRevert();
        levelMaster.setRewardPerSecond(1000 ether);
        vm.stopPrank();
    }

    function test_get_pending_rewards() external {
        initPool();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.warp(block.timestamp + 100);
        assertEq(levelMaster.pendingReward(0, user1), 150166666666666000000000);
    }

    function test_update_pools() external {
        initPool();
        uint256[] memory pids = new uint256[](1);
        pids[0] = 0;
        levelMaster.massUpdatePools(pids);
        (, uint256 lastRewardTime,,) = levelMaster.poolInfo(0);
        assertEq(lastRewardTime, block.timestamp);
        vm.startPrank(owner);
    }

    function test_deposit() external {
        initPool();
        vm.startPrank(user1);
        stakeToken.mint(1000e18);
        stakeToken.approve(address(levelMaster), 1000e18);
        // deposit  0 amount => revert
        vm.expectRevert();
        levelMaster.deposit(0, 0, user1);
        // success
        levelMaster.deposit(0, 1000e18, user1);
        vm.stopPrank();
    }

    function test_withdraw() external {
        initPool();
        fakeDiposit();
        vm.startPrank(user1);
        (uint256 balance,) = levelMaster.userInfo(0, user1);
        levelMaster.withdraw(0, 0, user1);
        assertEq(stakeToken.balanceOf(user1), 0);
        levelMaster.withdraw(0, balance, user1);
        assertEq(stakeToken.balanceOf(user1), balance);
        (balance,) = levelMaster.userInfo(0, user1);
        vm.stopPrank();

        vm.startPrank(user4);
        // amount is not enough => revert
        vm.expectRevert();
        levelMaster.withdraw(0, 1000e18, user4);
        vm.stopPrank();
    }

    function test_harvest() external {
        initPool();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.startPrank(user1);
        vm.warp(block.timestamp + 100);
        assertEq(levelMaster.pendingReward(0, user1), 150166666666666000000000);
        rewardToken.mintTo(150166666666666000000000, address(levelMaster));
        levelMaster.harvest(0, user1);
        assertEq(rewardToken.balanceOf(user1), 150166666666666000000000);
        vm.stopPrank();
    }

    function test_harvest_with_staking() external {
        vm.startPrank(owner);
        levelMaster.add(100, stakeToken, true, rewarder);
        levelMaster.setRewardPerSecond(10 ether);
        vm.stopPrank();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.startPrank(user1);
        vm.warp(block.timestamp + 100);
        assertEq(levelMaster.pendingReward(0, user1), 150166666666666000000000);
        rewardToken.mintTo(150166666666666000000000, address(levelMaster));
        levelMaster.harvest(0, user1);
        assertEq(rewardToken.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_withdraw_and_harvest() external {
        initPool();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.warp(block.timestamp + 100);
        vm.startPrank(user1);
        assertEq(levelMaster.pendingReward(0, user1), 150166666666666000000000);
        rewardToken.mintTo(150166666666666000000000, address(levelMaster));
        (uint256 balance,) = levelMaster.userInfo(0, user1);
        levelMaster.withdrawAndHarvest(0, balance, user1);
        assertEq(rewardToken.balanceOf(user1), 150166666666666000000000);
        assertEq(stakeToken.balanceOf(user1), balance);
        vm.stopPrank();
    }

    function test_harvest_all() external {
        initPool();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.warp(block.timestamp + 100);
        vm.startPrank(user1);
        rewardToken.mintTo(150166666666666000000000, address(levelMaster));
        levelMaster.harvestAll(user1);
        assertEq(rewardToken.balanceOf(user1), 150166666666666000000000);
        vm.stopPrank();
    }

    function test_add_liquidity() external {
        initPool();
        vm.startPrank(user1);
        btc.mint(1000e18);
        btc.approve(address(levelMaster), 1000e18);
        // amount = 0 => revert
        vm.expectRevert();
        levelMaster.addLiquidity(0, address(btc), 0, 0, user1);
        //
        levelMaster.addLiquidity(0, address(btc), 1000e18, 0, user1);
        vm.stopPrank();
    }

    function test_add_liquidity_eth() external {
        initPool();
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);
        // amount = 0 => revert
        vm.expectRevert();
        levelMaster.addLiquidityETH{value: 0 ether}(0, 0, user1);
        //
        levelMaster.addLiquidityETH{value: 100 ether}(0, 0, user1);
        vm.stopPrank();
    }

    function test_remove_liquidity() external {
        initPool();
        vm.startPrank(user1);
        btc.mint(1000e18);
        btc.approve(address(levelMaster), 1000e18);
        //
        levelMaster.addLiquidity(0, address(btc), 1000e18, 0, user1);
        // mock token to pool
        stakeToken.mintTo(1000e18, address(pool));
        levelMaster.removeLiquidity(0, 1000e18, address(stakeToken), 0, user1);
        vm.stopPrank();
    }

    function test_remove_liquidity_eth() external {
        initPool();
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);
        //
        levelMaster.addLiquidityETH{value: 100 ether}(0, 0, user1);
        // mock token to pool
        //  stakeToken.mintTo(1000e18, address(pool));
        levelMaster.removeLiquidityETH(0, 100 ether, 0, user1);
        vm.stopPrank();
    }

    function test_emergency_withdraw() external {
        initPool();
        // pending rewards = 0

        assertEq(levelMaster.pendingReward(0, user1), 0);
        // deposit
        fakeDiposit();
        vm.startPrank(user1);
        (uint256 balance,) = levelMaster.userInfo(0, user1);
        levelMaster.emergencyWithdraw(0, user1);
        assertEq(stakeToken.balanceOf(user1), balance);
        vm.stopPrank();
    }

    function initPool() internal {
        vm.startPrank(owner);
        levelMaster.add(100, stakeToken, false, rewarder);
        levelMaster.setRewardPerSecond(10 ether);
        vm.stopPrank();
    }

    function fakeDiposit() internal {
        vm.startPrank(user1);
        stakeToken.mint(1000e18);
        stakeToken.approve(address(levelMaster), 1000e18);
        levelMaster.deposit(0, 1000e18, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 10_000);
        vm.startPrank(user2);
        stakeToken.mint(2000e18);
        stakeToken.approve(address(levelMaster), 2000e18);
        levelMaster.deposit(0, 2000e18, user2);
        vm.stopPrank();

        vm.warp(block.timestamp + 15_000);
        vm.startPrank(user3);
        stakeToken.mint(3000e18);
        stakeToken.approve(address(levelMaster), 3000e18);
        levelMaster.deposit(0, 3000e18, user3);
        vm.stopPrank();
    }
}
