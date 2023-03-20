pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import "src/fund/LevelDevFund.sol";
import "src/tokens/LevelToken.sol";
import "src/tokens/LevelGovernance.sol";
import "src/farm/LevelStake.sol";
import "src/fund/Erc20Reserve.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy as Proxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LevelDevFundTest is Test {
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address ole = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;

    LevelDevFund devFund;
    LevelToken level;
    LevelGovernance lgo;
    LevelStake levelStake;
    // Erc20Reserve lgoReserve;

    uint256 public constant EPOCH = 365 days;
    uint256 public constant DURATION = 4 * EPOCH;
    uint256 public constant START = 1672063200; // December 26, 2022 9:00:00 PM GMT+07:00
    uint256 public constant ALLOCATION = 10_000_000 ether; // 10 M

    uint256 public constant COOLDOWN_SECONDS = 10 days;
    uint256 public constant UNSTAKE_WINDOWN = 2 days;

    uint256 public constant REWARD_PER_SECONDS = 1e12; // 0.000001 LGO per Second

    function setUp() external {
        vm.startPrank(owner);
        level = new LevelToken();

        address proxyAdmin = address(new ProxyAdmin());
        Proxy proxy = new Proxy(address( new LevelStake()), proxyAdmin, new bytes(0));
        levelStake = LevelStake(address(proxy));

        Proxy lgoProxy = new Proxy(address(new LevelGovernance()), proxyAdmin, new bytes(0));
        lgo = LevelGovernance(address(lgoProxy));
        lgo.initialize();

        levelStake.initialize(address(level), address(lgo), REWARD_PER_SECONDS);

        devFund = new LevelDevFund();
        devFund.initialize(address(levelStake));
        lgo.transfer(address(levelStake), 1_000 ether);

        vm.stopPrank();
    }

    function test_initialize() external {
        vm.startPrank(owner);

        LevelDevFund _devFund = new LevelDevFund();
        _devFund.initialize(address(levelStake));

        assertEq(address(_devFund.LVL()), address(level));
        assertEq(address(_devFund.LGO()), address(lgo));

        vm.stopPrank();
    }

    function _init() internal {
        vm.warp(START);
        vm.startPrank(owner);
        level.transfer((address(devFund)), ALLOCATION);
        devFund.stake(level.balanceOf(address(devFund)));
        vm.stopPrank();
    }

    function test_lock() external {
        vm.startPrank(owner);
        vm.warp(START);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        devFund.stake(ALLOCATION / 2);
        level.transfer((address(devFund)), ALLOCATION);
        devFund.stake(ALLOCATION / 2);
        devFund.stake(ALLOCATION / 2);
        assertEq(level.balanceOf(address(devFund)), 0);
        vm.stopPrank();
    }

    function test_claim_reward() external {
        _init();
        vm.startPrank(owner);
        vm.warp(START + EPOCH);
        uint256 estPending = EPOCH * REWARD_PER_SECONDS;
        uint256 pending = devFund.claimableLGO();
        assertEq(estPending, pending);
        devFund.claimLGO(ole, estPending);
        assertEq(lgo.balanceOf(ole), estPending);
    }

    function test_unstake_time() external {
        _init();
        vm.startPrank(owner);
        (uint256 start, uint256 end) = devFund.getUnstakeTime();
        assertEq(start, 0);
        assertEq(end, 0);
        vm.warp(START + 10);
        devFund.cooldown();
        (start, end) = devFund.getUnstakeTime();
        // cooldown removed
        assertEq(start, 0);
        assertEq(end, 0);
    }

    function test_claim_in_epoch1() external {
        _init();
        uint256 EXPECT = ALLOCATION / 4;

        vm.warp(START + 10);
        vm.startPrank(owner);

        devFund.cooldown();
        vm.warp(START + 10 + COOLDOWN_SECONDS + 1);

        uint256 unlocked = devFund.claimableLVL();
        console.log("unlocked", unlocked);
        assertEq(unlocked, 0, "Nothing should unlocked yet");

        vm.expectRevert("LevelDevFund::withdraw: invalid amount");
        devFund.withdraw(0, alice);

        vm.expectRevert("LevelDevFund::withdraw: invalid amount");
        devFund.withdraw(1, alice);

        vm.warp(START + EPOCH);

        devFund.cooldown();
        vm.warp(START + EPOCH + COOLDOWN_SECONDS + 1);
        unlocked = devFund.claimableLVL();

        assertEq(unlocked, EXPECT);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        devFund.withdraw(unlocked, alice);

        devFund.unstake(unlocked);
        devFund.withdraw(unlocked, alice);

        uint256 _unlockedAfterClaim = devFund.claimableLVL();
        assertEq(_unlockedAfterClaim, 0);
    }

    function test_multiple_claim() external {
        _init();
        uint256 EXPECT = ALLOCATION / 4;

        vm.startPrank(owner);
        // EPOCH 1

        vm.warp(START + EPOCH);

        uint256 unlocked = devFund.claimableLVL();
        assertEq(unlocked, EXPECT);

        devFund.cooldown();
        vm.warp(START + EPOCH + COOLDOWN_SECONDS + 1);
        devFund.unstake(unlocked);

        devFund.withdraw(unlocked, alice);
        assertEq(level.balanceOf(alice), EXPECT);

        uint256 _unlockedAfterClaim = devFund.claimableLVL();
        assertEq(_unlockedAfterClaim, 0);

        // EPOCH 3

        vm.warp(START + (EPOCH * 3));
        unlocked = devFund.claimableLVL();
        assertEq(unlocked, EXPECT * 2);

        devFund.cooldown();
        vm.warp(START + (EPOCH * 3) + COOLDOWN_SECONDS + 1);

        devFund.unstake(unlocked);
        devFund.withdraw(unlocked, alice);
        assertEq(level.balanceOf(alice), EXPECT * 3);

        uint256 _unlockedAfterClaim2 = devFund.claimableLVL();
        assertEq(_unlockedAfterClaim2, 0);

        // OVERTIME

        vm.warp(START + (EPOCH * 4));
        unlocked = devFund.claimableLVL();
        assertEq(unlocked, EXPECT);

        devFund.cooldown();
        vm.warp(START + (EPOCH * 4) + COOLDOWN_SECONDS + 1);

        devFund.unstake(unlocked);
        devFund.withdraw(unlocked, alice);
        assertEq(level.balanceOf(alice), ALLOCATION);

        uint256 _unlockedAfterClaim3 = devFund.claimableLVL();
        assertEq(_unlockedAfterClaim3, 0);
    }
}
