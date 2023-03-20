pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/referral/LevelReferralRegistry.sol";
import "../src/referral/LevelReferralControllerV2.sol";
import "../src/oracle/LVLOracle.sol";
import "./mocks/MockPool.sol";
import "./mocks/MockUniswapPair.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy as Proxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TestLevelReferralController is LevelReferralControllerV2 {
    function update() external {
        delete tiers[0];
        delete tiers[1];
        delete tiers[2];
        delete tiers[3];
        tiers.push(TierInfo({minTrader: 0, minEpochReferralPoint: 0, discountForTrader: 0, rebateForReferrer: 0}));
        tiers.push(
            TierInfo({minTrader: 1, minEpochReferralPoint: 10e30, discountForTrader: 5e4, rebateForReferrer: 10e4})
        );
        tiers.push(
            TierInfo({minTrader: 2, minEpochReferralPoint: 20e30, discountForTrader: 10e4, rebateForReferrer: 10e4})
        );
        tiers.push(
            TierInfo({minTrader: 3, minEpochReferralPoint: 30e30, discountForTrader: 10e4, rebateForReferrer: 15e4})
        );
    }
}

contract LevelReferralTest is Test {
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address bob = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address dee = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address eve = 0x2E20CFb2f7f98Eb5c9FD31Df41620872C0aef524;

    uint256 private constant REBATE_PRECISION = 1e6;

    LevelReferralRegistry levelReferralRegistry;
    TestLevelReferralController levelReferralController;
    LVLOracle oracle;
    uint256 lastTimestamp;

    uint256 public epochDuration = 7 days;

    MockERC20 LVL;
    MockERC20 WBNB;
    MockERC20 BUSD;
    MockUniswapPair lvlBnbPair;
    MockUniswapPair bnbBusdPair;
    ProxyAdmin proxyAdmin = new ProxyAdmin();

    function setUp() external {
        vm.startPrank(owner);
        LVL = new MockERC20("LVL", "LVL", 18);
        WBNB = new MockERC20("WBNB", "WBNB", 18);
        WBNB = new MockERC20("BUSD", "BUSD", 18);

        lvlBnbPair = new MockUniswapPair(address(LVL), address(WBNB));
        bnbBusdPair = new MockUniswapPair(address(WBNB), address(BUSD));

        Proxy registryProxy = new Proxy(address(new LevelReferralRegistry()), address(proxyAdmin), new bytes(0));
        levelReferralRegistry = LevelReferralRegistry(address(registryProxy));
        levelReferralRegistry.initialize();

        Proxy controllerProxy = new Proxy(address(new TestLevelReferralController()), address(proxyAdmin), new bytes(0));
        levelReferralController = TestLevelReferralController(address(controllerProxy));

        oracle = new LVLOracle();
        oracle.initialize(
            address(LVL), address(WBNB), address(lvlBnbPair), address(bnbBusdPair), address(levelReferralController)
        );

        levelReferralController.initialize(address(LVL), address(oracle), address(levelReferralRegistry), 7 days);

        levelReferralController.start(block.timestamp);

        levelReferralController.update();

        levelReferralRegistry.setController(address(levelReferralController));

        levelReferralController.setUpdater(owner);
        levelReferralController.setDistributor(owner);
        levelReferralController.setEnableNextEpoch(true);

        lastTimestamp = block.timestamp;

        vm.stopPrank();
    }

    function test_withdraw_lvl() external {
        vm.expectRevert("Ownable: caller is not the owner");
        levelReferralController.withdrawLVL(owner, 1 ether);

        vm.startPrank(owner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        levelReferralController.withdrawLVL(owner, 1 ether);

        LVL.mintTo(1 ether, address(levelReferralController));
        vm.expectRevert("LevelReferralController::withdrawLVL: invalid address");
        levelReferralController.withdrawLVL(address(0), 1 ether);

        levelReferralController.withdrawLVL(owner, 1 ether);
    }

    function test_next_epoch() external {
        assertEq(levelReferralController.currentEpoch(), 4);

        vm.startPrank(owner);
        vm.expectRevert("LevelReferralController::nextEpoch: now < trigger time");
        levelReferralController.nextEpoch();
        vm.warp(lastTimestamp + epochDuration * 2);
        levelReferralController.nextEpoch();

        vm.warp(lastTimestamp + epochDuration * 4);
        levelReferralController.nextEpoch();
        vm.warp(lastTimestamp + epochDuration * 5);
        levelReferralController.nextEpoch();
        vm.stopPrank();
        vm.startPrank(alice);
        vm.warp(lastTimestamp + epochDuration * 6);
        vm.expectRevert("LevelReferralController::setEnableNextEpoch: !distributor");
        levelReferralController.setEnableNextEpoch(false);
        vm.stopPrank();
        vm.startPrank(owner);
        levelReferralController.setEnableNextEpoch(false);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("LevelReferralController::nextEpoch: !enableNextEpoch");
        levelReferralController.nextEpoch();
        vm.stopPrank();
    }

    function test_set_epoch_duration() external {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        levelReferralController.setEpochDuration(epochDuration);

        vm.startPrank(owner);
        vm.expectRevert("LevelReferralController::setEpochDuration: must >= MIN_EPOCH_DURATION");
        levelReferralController.setEpochDuration(epochDuration / 10);

        levelReferralController.setEpochDuration(epochDuration);
    }

    function test_control_updater_and_update_point() external {
        vm.startPrank(dee);
        vm.expectRevert("Ownable: caller is not the owner");
        levelReferralController.setUpdater(dee);
        vm.expectRevert("LevelReferralController::updatePoint: !updater");
        levelReferralController.updatePoint(dee, 10e18);
        vm.stopPrank();

        vm.startPrank(owner);
        levelReferralController.setUpdater(dee);
        // levelReferralController.start();
        vm.stopPrank();

        vm.startPrank(dee);
        vm.expectRevert("LevelReferralController::updatePoint: invalid address");
        levelReferralController.updatePoint(address(0), 10e18);
        levelReferralController.updatePoint(alice, 10e18);
    }

    // Level 1: 1 user | 10 point | trader 5% | referrer 10%
    // Level 2: 2 user | 20 point | trader 10% | referrer 10%
    // Level 3: 3 user | 30 point | trader 10% | referrer 15%
    function test_update_level() external {
        // vm.startPrank(owner);
        // vm.expectRevert("LevelReferralController::setReferrer: !started");
        // levelReferralController.setReferrer(alice);
        // levelReferralController.start();
        // vm.stopPrank();

        vm.prank(alice);
        levelReferralController.setReferrer(owner);
        vm.prank(bob);
        levelReferralController.setReferrer(owner);
        vm.prank(dee);
        levelReferralController.setReferrer(owner);

        vm.startPrank(owner);
        levelReferralController.updatePoint(alice, 1e18);
        levelReferralController.updatePoint(bob, 1e18);
        levelReferralController.updatePoint(dee, 8e18);

        levelReferralController.updatePoint(dee, 100e18);

        levelReferralController.updatePoint(dee, 500e18);
    }

    // Level 1: 1 user | 10 point | trader 5% | referrer 10%
    // Level 2: 2 user | 20 point | trader 10% | referrer 10%
    // Level 3: 3 user | 30 point | trader 10% | referrer 15%
    function test_claim_referral_role_level2() external {
        // owner invite alice and bob, bod trade 10 BUSD and alice trade 10 BUSD => owner level 2

        // vm.startPrank(owner);
        // levelReferralController.start();
        // vm.stopPrank();

        uint256 currentEpoch = levelReferralController.currentEpoch();

        vm.prank(alice);
        levelReferralController.setReferrer(owner);
        vm.prank(bob);
        levelReferralController.setReferrer(owner);

        vm.startPrank(owner);
        levelReferralController.updatePoint(alice, 10e30);
        levelReferralController.updatePoint(bob, 10e30);

        vm.expectRevert("LevelReferralController::nextEpoch: now < trigger time");
        levelReferralController.nextEpoch();

        vm.warp(epochDuration * 2);
        levelReferralController.nextEpoch();

        uint256 price = oracle.lastTWAP();

        assertEq(levelReferralController.claimable(currentEpoch + 1, owner), 0);
        assertEq(levelReferralController.claimable(currentEpoch + 1, alice), 0);
        assertEq(levelReferralController.claimable(currentEpoch, alice), 1e30 / price); // 10% of 10 BUSD = 1 BUSD
        assertEq(levelReferralController.claimable(currentEpoch, bob), 1e30 / price); // 10% of 10 BUSD = 1 BUSD
        assertEq(levelReferralController.claimable(currentEpoch, owner), 2e30 / price); // 10% of 20 BUSD = 2 BUSD

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        levelReferralController.claim(currentEpoch, owner);
        LVL.mintTo(100e18, address(levelReferralController));

        levelReferralController.claim(currentEpoch, owner);
        assertEq(LVL.balanceOf(address(owner)), 2e30 / price);
    }

    // Level 1: 1 user | 10 point | trader 5% | referrer 10%
    // Level 2: 2 user | 20 point | trader 10% | referrer 10%
    // Level 3: 3 user | 30 point | trader 10% | referrer 15%
    function test_claim_referral_role_level2_and_trade_level1() external {
        // owner invite alice and bob, bod trade 10 BUSD and alice trade 10 BUSD => owner level 2
        // dee invite owner, owner trade 10 BUSD => dee level 1

        // vm.startPrank(owner);
        // levelReferralController.start();
        // vm.stopPrank();

        uint256 currentEpoch = levelReferralController.currentEpoch();
        vm.prank(alice);
        levelReferralController.setReferrer(owner);
        vm.prank(bob);
        levelReferralController.setReferrer(owner);

        vm.startPrank(owner);
        levelReferralController.updatePoint(alice, 10e30);
        levelReferralController.updatePoint(bob, 10e30);

        levelReferralController.setReferrer(dee);
        levelReferralController.updatePoint(owner, 10e30);
        vm.warp(epochDuration * 2);
        levelReferralController.nextEpoch();

        uint256 price = oracle.lastTWAP();

        assertEq(levelReferralController.claimable(currentEpoch, alice), 1e30 / price); // 10% of 10 BUSD = 1 BUSD
        assertEq(levelReferralController.claimable(currentEpoch, bob), 1e30 / price); // 10% of 10 BUSD = 1 BUSD
        assertEq(levelReferralController.claimable(currentEpoch, dee), 1e30 / price); // 10% of 10 BUSD = 1 BUSD
        assertEq(levelReferralController.claimable(currentEpoch, owner), 25e29 / price); // 10% of 20 BUSD + 5% of 10 BUSD = 2.5 BUSD

        LVL.mintTo(100e18, address(levelReferralController));

        levelReferralController.claim(currentEpoch, owner);
        assertEq(LVL.balanceOf(address(owner)), 25e29 / price);
        vm.stopPrank();

        vm.startPrank(dee);
        levelReferralController.claim(currentEpoch, dee);
        assertEq(LVL.balanceOf(address(dee)), (1e30) / price);
        vm.stopPrank();
    }

    // Level 1: 1 user | 10 point | trader 5% | referrer 10%
    // Level 2: 2 user | 20 point | trader 10% | referrer 10%
    // Level 3: 3 user | 30 point | trader 10% | referrer 15%
    function test_vesting_claim_referral_role_level2() external {
        // owner invite alice and bob, bod trade 10 BUSD and alice trade 10 BUSD => owner level 2

        vm.startPrank(owner);
        levelReferralController.setEpochVestingDuration(1 days);
        LVL.mintTo(100e18, address(levelReferralController));
        vm.stopPrank();

        uint256 currentEpoch = levelReferralController.currentEpoch();

        vm.prank(alice);
        levelReferralController.setReferrer(owner);
        vm.prank(bob);
        levelReferralController.setReferrer(owner);

        vm.startPrank(owner);
        levelReferralController.updatePoint(alice, 10e30);
        levelReferralController.updatePoint(bob, 10e30);

        vm.warp(epochDuration * 2);
        levelReferralController.nextEpoch();

        uint256 price = oracle.lastTWAP();

        uint256 aliceReward = 1e30 / price; // 10% of 10 BUSD = 1 BUSD
        uint256 bobReward = 1e30 / price; // 10% of 10 BUSD = 1 BUSD
        uint256 ownerReward = 2e30 / price; // 10% of 20 BUSD = 2 BUSD

        vm.warp((epochDuration * 2) + 1);
        assertEq(levelReferralController.claimable(currentEpoch, alice), aliceReward / 1 days);
        assertEq(levelReferralController.claimable(currentEpoch, bob), bobReward / 1 days);
        assertEq(levelReferralController.claimable(currentEpoch, owner), ownerReward / 1 days);

        levelReferralController.claim(currentEpoch, owner);
        assertEq(LVL.balanceOf(address(owner)), ownerReward / 1 days);

        vm.warp((epochDuration * 2) + 0.5 days);
        assertEq(levelReferralController.claimable(currentEpoch, alice), aliceReward / 2);
        assertEq(levelReferralController.claimable(currentEpoch, bob), bobReward / 2);
        assertEq(levelReferralController.claimable(currentEpoch, owner), ownerReward / 2 - (ownerReward / 1 days));

        levelReferralController.claim(currentEpoch, owner);
        assertEq(LVL.balanceOf(address(owner)), ownerReward / 2);

        vm.warp((epochDuration * 2) + 2 days);
        assertEq(levelReferralController.claimable(currentEpoch, alice), aliceReward);
        assertEq(levelReferralController.claimable(currentEpoch, bob), bobReward);
        assertEq(levelReferralController.claimable(currentEpoch, owner), ownerReward / 2);

        levelReferralController.claim(currentEpoch, owner);
        assertEq(LVL.balanceOf(address(owner)), ownerReward);

        vm.warp((epochDuration * 2) + 3 days);
        vm.expectRevert("LevelReferralController::claim: !reward");
        levelReferralController.claim(currentEpoch, owner);
    }

    // Level 1: 1 user | 10 point | trader 5% | referrer 10%
    // Level 2: 2 user | 20 point | trader 10% | referrer 10%
    // Level 3: 3 user | 30 point | trader 10% | referrer 15%
    function test_claim_old_epoch_reward() external {
        vm.startPrank(owner);
        LVL.mintTo(100e18, address(levelReferralController));
        vm.stopPrank();

        uint256 currentEpoch = levelReferralController.currentEpoch();

        vm.prank(alice);
        levelReferralController.setReferrer(owner);

        vm.startPrank(owner);
        levelReferralController.updatePoint(alice, 20e30);
        vm.warp(epochDuration * 2);
        levelReferralController.nextEpoch();
        vm.stopPrank();

        uint256 price = oracle.lastTWAP();

        uint256 aliceReward = 1e30 / price; // 5% of 20 BUSD = 1 BUSD

        vm.warp((epochDuration * 2) + 1);
        assertEq(levelReferralController.claimable(currentEpoch, alice), aliceReward);

        vm.prank(alice);
        levelReferralController.claim(currentEpoch, alice);
        assertEq(LVL.balanceOf(alice), aliceReward);

        vm.prank(bob);
        levelReferralController.setReferrer(owner);

        assertEq(levelReferralController.claimable(currentEpoch, alice), 0);
    }
}
