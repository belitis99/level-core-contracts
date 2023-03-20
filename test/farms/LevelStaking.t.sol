// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "src/tokens/LevelToken.sol";
import "src/tokens/LevelGovernance.sol";
import "src/farm/LevelStake.sol";
import "src/fund/Erc20Reserve.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy as Proxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LevelStakeTest is Test {
    address owner = 0xCE2ee0D3666342d263F534e9375c1A450AC7624d;
    address alice = 0xA6Cc2e3d88e0B510C1c0157F867a6294d2FAB0F1;
    address ole = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address treasury = vm.addr(uint256(keccak256(abi.encodePacked("treasury"))));

    uint256 public constant COOLDOWN_SECONDS = 10 days;
    uint256 public constant UNSTAKE_WINDOWN = 2 days;
    uint256 public constant REWARD_PER_SECONDS = 1e14; // 0.001 LGO per Second
    uint256 public constant BOOSTED_REWARD_PER_SECONDS = 1e13; // 0.001 LGO per Second

    uint256 START = COOLDOWN_SECONDS + UNSTAKE_WINDOWN + 1;

    LevelToken level;
    LevelGovernance levelGovernance;
    LevelStake levelStake;

    function setUp() external {
        init();
    }

    function test_stake() external {
        vm.startPrank(owner);
        vm.warp(START);
        level.approve(address(levelStake), type(uint256).max);
        // amoun = 0 => expect revert
        vm.expectRevert();
        levelStake.stake(alice, 0);
        //success
        levelStake.stake(alice, 1e18);
        levelStake.stake(ole, 4e18);

        vm.warp(START + COOLDOWN_SECONDS);
        assertEq(levelStake.pendingReward(alice), REWARD_PER_SECONDS * COOLDOWN_SECONDS * 1e18 / 5e18);
        assertEq(levelStake.pendingReward(ole), REWARD_PER_SECONDS * COOLDOWN_SECONDS * 4e18 / 5e18);
        //stake more
        levelStake.stake(alice, 1e18);
        levelStake.stake(ole, 4e18);
        vm.stopPrank();
    }

    function test_unstake() external {
        vm.startPrank(owner);
        // nothing fund
        levelStake.reserveAuctionFund(1000 ether);
        vm.warp(START);
        level.approve(address(levelStake), type(uint256).max);
        levelStake.stake(alice, 1e18);
        levelStake.stake(ole, 4e18);
        vm.stopPrank();
        vm.warp(START + COOLDOWN_SECONDS);
        assertEq(levelStake.pendingReward(alice), REWARD_PER_SECONDS * COOLDOWN_SECONDS * 1e18 / 5e18);
        assertEq(levelStake.pendingReward(ole), REWARD_PER_SECONDS * COOLDOWN_SECONDS * 4e18 / 5e18);

        // Unstake
        vm.warp(START + COOLDOWN_SECONDS * 2);
        vm.startPrank(alice);
        // amoun =0 => revert
        vm.expectRevert();
        levelStake.unstake(alice, 0);
        //success
        levelStake.unstake(alice, 1e18);
        assertEq(level.balanceOf(alice), 1e18);
        assertEq(levelStake.pendingReward(alice), 0);

        assertEq(levelStake.pendingReward(ole), REWARD_PER_SECONDS * (COOLDOWN_SECONDS * 2) * 4e18 / 5e18);
    }

    function test_claim_reward_with_boosted_reward() external {
        vm.startPrank(owner);
        vm.warp(START);

        uint256 currentTotalReward;
        uint256 aliceReward;
        uint256 oleReward;

        // Alice and Ole stake
        {
            level.approve(address(levelStake), type(uint256).max);
            levelStake.stake(alice, 1e18);
            levelStake.stake(ole, 4e18);
        }
        // Calc pending reward after stake with COOLDOWN_SECONDS duration
        {
            vm.warp(START + COOLDOWN_SECONDS);
            currentTotalReward = REWARD_PER_SECONDS * COOLDOWN_SECONDS;
            aliceReward = currentTotalReward * 1e18 / 5e18;
            oleReward = currentTotalReward * 4e18 / 5e18;
            assertEq(levelStake.pendingReward(alice), aliceReward);
            assertEq(levelStake.pendingReward(ole), oleReward);
        }
        // Set boosted reward
        {
            levelStake.setBooster(owner);
            levelStake.setBoostedReward(BOOSTED_REWARD_PER_SECONDS, COOLDOWN_SECONDS);
        }
        vm.stopPrank();
        // Calc pending reward after set boosted reward with COOLDOWN_SECONDS duration
        {
            vm.warp(START + COOLDOWN_SECONDS * 2);
            currentTotalReward = currentTotalReward + (REWARD_PER_SECONDS * COOLDOWN_SECONDS)
                + (BOOSTED_REWARD_PER_SECONDS * COOLDOWN_SECONDS);
            aliceReward = currentTotalReward * 1e18 / 5e18;
            oleReward = currentTotalReward * 4e18 / 5e18;
            assertEq(levelStake.pendingReward(alice), aliceReward);
            assertEq(levelStake.pendingReward(ole), oleReward);
        }
        // Alice unstake
        {
            vm.prank(alice);
            levelStake.unstake(alice, 1e18);
            aliceReward = 0;
            assertEq(level.balanceOf(alice), 1e18);
            assertEq(levelStake.pendingReward(alice), aliceReward);
            assertEq(levelStake.pendingReward(ole), oleReward);
        }
        // Calc pending reward after alice unstake with COOLDOWN_SECONDS duration
        {
            vm.warp(START + COOLDOWN_SECONDS * 3);

            currentTotalReward = REWARD_PER_SECONDS * COOLDOWN_SECONDS;
            oleReward = oleReward + currentTotalReward;
            assertEq(levelStake.pendingReward(alice), 0);
            assertEq(levelStake.pendingReward(ole), oleReward);
            vm.prank(ole);
            levelStake.claimRewards(ole);
            assertEq(levelStake.pendingReward(ole), 0);
        }
    }

    function test_set_booster() external {
        // Not Owner => revert
        vm.expectRevert();
        levelStake.setBooster(owner);

        vm.startPrank(owner);
        // Address is 0x0 => revert
        vm.expectRevert();
        levelStake.setBooster(address(0));
        // Success
        levelStake.setBooster(owner);
        assertEq(levelStake.booster(), owner);
        vm.stopPrank();
    }

    function test_set_reward_per_second() external {
        // Not Owner => revert
        vm.expectRevert();
        levelStake.setRewardPerSecond(0.1 ether);

        vm.startPrank(owner);
        // > MAX => revert
        vm.expectRevert();
        levelStake.setRewardPerSecond(1.1 ether);
        // Success
        levelStake.setRewardPerSecond(1 ether);
        assertEq(levelStake.rewardPerSecond(), 1 ether);
        vm.stopPrank();
    }

    function test_reserve_auction_fund() external {
        vm.startPrank(owner);
        levelStake.reserveAuctionFund(10 ether);
        vm.stopPrank();
    }

    function test_override_boosted_reward() external {
        vm.warp(START);
        vm.startPrank(owner);

        level.approve(address(levelStake), type(uint256).max);
        uint256 aliceReward;

        // Alice stake and set boosted reward
        {
            levelStake.setBooster(owner);
            levelStake.stake(alice, 1e18);

            // Not booster => revert
            vm.stopPrank();
            vm.prank(alice);
            vm.expectRevert();
            levelStake.setBoostedReward(BOOSTED_REWARD_PER_SECONDS, COOLDOWN_SECONDS);

            vm.startPrank(owner);
            // > MAX_BOOSTED_REWARD_PER_SECOND, revert
            vm.expectRevert();
            levelStake.setBoostedReward(100 ether, COOLDOWN_SECONDS);

            // duration == 0, revert
            vm.expectRevert();
            levelStake.setBoostedReward(BOOSTED_REWARD_PER_SECONDS, 0);

            //
            levelStake.setBoostedReward(BOOSTED_REWARD_PER_SECONDS, COOLDOWN_SECONDS);
        }
        // Override boosted reward
        {
            vm.warp(START + (COOLDOWN_SECONDS / 2));
            levelStake.setBoostedReward(BOOSTED_REWARD_PER_SECONDS, COOLDOWN_SECONDS);
            vm.stopPrank();
        }
        // Calc pending reward when boosted reward end
        {
            vm.warp(START + (COOLDOWN_SECONDS / 2) + COOLDOWN_SECONDS);

            aliceReward = (BOOSTED_REWARD_PER_SECONDS + REWARD_PER_SECONDS) * COOLDOWN_SECONDS * 3 / 2;
            assertEq(levelStake.pendingReward(alice), aliceReward);
        }
        // Next pending reward
        {
            vm.warp(START + (COOLDOWN_SECONDS / 2) + COOLDOWN_SECONDS + (COOLDOWN_SECONDS / 2));

            aliceReward =
                (BOOSTED_REWARD_PER_SECONDS * COOLDOWN_SECONDS * 3 / 2) + (REWARD_PER_SECONDS * COOLDOWN_SECONDS * 2);
            assertEq(levelStake.pendingReward(alice), aliceReward);
        }
        // Alice unstake
        {
            vm.prank(alice);
            levelStake.unstake(alice, 1e18);

            assertEq(levelGovernance.balanceOf(alice), aliceReward);
        }
    }

    function test_init() external {
        vm.startPrank(owner);
        LevelToken _level = new LevelToken();

        address proxyAdmin = address(new ProxyAdmin());

        //
        Proxy proxy = new Proxy(address(new LevelGovernance()), proxyAdmin, new bytes(0));
        LevelGovernance _levelGovernance = LevelGovernance(address(proxy));
        _levelGovernance.initialize();

        Proxy levelStakeProxy = new Proxy(address(new LevelStake()), proxyAdmin, new bytes(0));
        LevelStake _levelStake = LevelStake(address(levelStakeProxy));
        // > MAX => revert
        vm.expectRevert();
        _levelStake.initialize(address(level), address(levelGovernance), 100 ether);

        // > level = 0x0 => revert
        vm.expectRevert();
        _levelStake.initialize(address(0), address(levelGovernance), REWARD_PER_SECONDS);

        // > levelGovernance = 0x0 => revert
        vm.expectRevert();
        _levelStake.initialize(address(level), address(0), REWARD_PER_SECONDS);
        // success
        _levelStake.initialize(address(level), address(levelGovernance), REWARD_PER_SECONDS);

        // address = 0x0 => revert
        vm.expectRevert();
        _levelStake.reinit_addAuctionTreasury(address(0));
        // successs
        _levelStake.reinit_addAuctionTreasury(treasury);
        vm.stopPrank();
    }

    function test_cooldown() external {
        vm.startPrank(owner);
        vm.warp(START);
        level.approve(address(levelStake), type(uint256).max);
        levelStake.stake(owner, 1e18);
        vm.warp(START + COOLDOWN_SECONDS);

        vm.warp(START + COOLDOWN_SECONDS * 2);
        levelStake.cooldown();
        levelStake.cooldown();
        levelStake.deactivateCooldown();
        levelStake.unstake(owner, 1e18);
        levelStake.cooldown();
        levelStake.deactivateCooldown();
    }

    function init() internal {
        vm.startPrank(owner);
        level = new LevelToken();

        address proxyAdmin = address(new ProxyAdmin());

        //
        Proxy proxy = new Proxy(address(new LevelGovernance()), proxyAdmin, new bytes(0));
        levelGovernance = LevelGovernance(address(proxy));
        levelGovernance.initialize();

        Proxy levelStakeProxy = new Proxy(address(new LevelStake()), proxyAdmin, new bytes(0));
        levelStake = LevelStake(address(levelStakeProxy));
        levelStake.initialize(address(level), address(levelGovernance), REWARD_PER_SECONDS);
        levelGovernance.transfer(address(levelStake), 1000 ether);
        levelStake.reinit_addAuctionTreasury(treasury);
        vm.warp(0);

        vm.stopPrank();
    }
}
