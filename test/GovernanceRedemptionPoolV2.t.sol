// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20BurnableMock} from "openzeppelin/mocks/ERC20BurnableMock.sol";
import {Address} from "openzeppelin/utils/Address.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/treasury/Treasury.sol";
import "../src/treasury/LGOStakingView.sol";
import "../src/treasury/GovernanceRedemptionPoolV2.sol";
import "../src/tokens/LevelGovernance.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";

contract GovernanceRedemptionPoolV2Test is Test {
    address owner = 0xCE2ee0D3666342d263F534e9375c1A450AC7624d;
    address alice = 0xA6Cc2e3d88e0B510C1c0157F867a6294d2FAB0F1;
    address bob = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;

    uint256 rewardsPerSecond = 7928240740741;
    uint256 startTimestamp = 1672063200;

    Treasury treasury;
    MockPool pool;

    ERC20BurnableMock lgo;

    LGOStakingView lgoStakingView;
    GovernanceRedemptionPoolV2 governanceRedemptionPool;

    MockERC20 PancakeLP;
    MockERC20 SLP;
    MockERC20 BTC;
    WETH9 WETH;
    ETHUnwrapper ethUnwrapper;

    uint256 DEV_RESERVE_RATIO = 20;
    uint256 RATIO_PRECISION = 100;

    function setUp() external {
        vm.startPrank(owner);

        PancakeLP = new MockERC20("PLP", "SLP", 18);
        SLP = new MockERC20("SLP", "SLP", 18);
        BTC = new MockERC20("BTC", "BTC", 18);
        WETH = new WETH9();
        pool = new MockPool();
        ethUnwrapper = new ETHUnwrapper(address(WETH));

        pool.setFeeReserve(address(SLP), 1 ether);
        BTC.mintTo(1 ether, address(pool));

        address proxyAdmin = address(bytes20("proxy-admin"));

        Treasury treasuryImpl = new Treasury();
        Proxy proxy = new Proxy(address(treasuryImpl), proxyAdmin, new bytes(0));
        treasury = Treasury(address(proxy));

        treasury.initialize(address(pool));
        treasury.reinit_v3(address(WETH), address(ethUnwrapper), address(SLP));
        treasury.reinit_v4(address(PancakeLP));
        treasury.grantRole(treasury.CONTROLLER_ROLE(), owner);
        treasury.setLLPToken(address(SLP));
        treasury.addWithdrawableToken(address(BTC));
        treasury.addWithdrawableToken(address(WETH));
        deal(address(SLP), address(treasury), 1 ether);

        lgo = new ERC20BurnableMock("LGO", "LGO", owner, 1000 ether);

        lgoStakingView = new LGOStakingView(address(lgo));

        GovernanceRedemptionPoolV2 redeemPoolImpl = new GovernanceRedemptionPoolV2();
        proxy = new Proxy(address(redeemPoolImpl), proxyAdmin, new bytes(0));
        governanceRedemptionPool = GovernanceRedemptionPoolV2(address(proxy));
        governanceRedemptionPool.initialize(address(SLP), address(lgo), address(lgoStakingView), address(treasury));
        governanceRedemptionPool.reinit_v2(address(PancakeLP));
        governanceRedemptionPool.grantRole(governanceRedemptionPool.ADMIN_ROLE(), owner);

        treasury.setLgoRedemptionPool(address(governanceRedemptionPool));

        vm.stopPrank();
    }

    function test_start_next_batch() external {
        vm.startPrank(owner);
        vm.expectRevert();
        governanceRedemptionPool.startNextBatch();
        governanceRedemptionPool.grantRole(governanceRedemptionPool.CONTROLLER_ROLE(), owner);
        governanceRedemptionPool.setRedeemDuration(1 days);
        governanceRedemptionPool.startNextBatch();
        vm.stopPrank();
    }

    function initRedemptionPool() internal {
        vm.warp(startTimestamp);
        governanceRedemptionPool.grantRole(governanceRedemptionPool.CONTROLLER_ROLE(), owner);
        governanceRedemptionPool.setRedeemDuration(1 days);
    }

    function test_redeem() external {
        vm.startPrank(owner);
        lgo.transfer(alice, rewardsPerSecond * 6);
        lgo.transfer(bob, rewardsPerSecond * 4);
        initRedemptionPool();

        vm.warp(startTimestamp + 10);
        governanceRedemptionPool.startNextBatch();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 slpInTreasury = SLP.balanceOf(address(treasury));

        vm.expectRevert("GovernanceRedemptionPool::redeem: !redeemable");
        governanceRedemptionPool.redeem(alice, 5 ether);

        uint256 aliceLgoBalance = lgo.balanceOf(alice);
        console.log("aliceLgoBalance", aliceLgoBalance);
        vm.expectRevert("ERC20: insufficient allowance");
        governanceRedemptionPool.redeem(alice, aliceLgoBalance);

        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(alice));
        governanceRedemptionPool.redeem(alice, lgo.balanceOf(alice));
        assertEq(SLP.balanceOf(alice), slpInTreasury * 6 / 10);
        assertEq(SLP.balanceOf(address(treasury)), slpInTreasury * 4 / 10);
        vm.stopPrank();

        vm.startPrank(bob);
        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(bob));
        governanceRedemptionPool.redeem(bob, lgo.balanceOf(bob));
        assertEq(SLP.balanceOf(alice), slpInTreasury * 6 / 10);
        assertEq(SLP.balanceOf(bob), slpInTreasury * 4 / 10);
        assertEq(SLP.balanceOf(address(treasury)), 0);
    }

    function test_redeem_to_token() external {
        vm.startPrank(owner);

        lgo.transfer(alice, rewardsPerSecond * 6);
        lgo.transfer(bob, rewardsPerSecond * 4);
        initRedemptionPool();

        vm.warp(startTimestamp + 10);
        governanceRedemptionPool.startNextBatch();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 slpInTreasury = BTC.balanceOf(address(treasury));

        vm.expectRevert("GovernanceRedemptionPool::redeemToToken: !redeemable");
        governanceRedemptionPool.redeemToToken(alice, 5 ether, address(BTC), 0);

        uint256 aliceLgoBalance = lgo.balanceOf(alice);
        vm.expectRevert("ERC20: insufficient allowance");
        governanceRedemptionPool.redeemToToken(alice, aliceLgoBalance, address(BTC), 0);

        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(alice));
        assertEq(BTC.balanceOf(alice), 0);
        governanceRedemptionPool.redeemToToken(alice, lgo.balanceOf(alice), address(BTC), 0);
        assertEq(BTC.balanceOf(address(treasury)), slpInTreasury * 4 / 10);
        vm.stopPrank();

        vm.startPrank(bob);
        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(bob));
        governanceRedemptionPool.redeemToToken(bob, lgo.balanceOf(bob), address(BTC), 0);
        assertEq(BTC.balanceOf(address(treasury)), 0);
    }

    function test_redeem_to_native_token() external {
        vm.startPrank(owner);

        vm.deal(owner, 100 ether);
        Address.sendValue(payable(WETH), 100 ether);
        WETH.transfer(address(pool), 100 ether);
        pool.setPoolBalance(address(WETH), 100 ether);

        lgo.transfer(alice, rewardsPerSecond * 6);
        lgo.transfer(bob, rewardsPerSecond * 4);
        initRedemptionPool();

        vm.warp(startTimestamp + 10);
        governanceRedemptionPool.startNextBatch();
        vm.stopPrank();

        vm.startPrank(alice);
        assertEq(alice.balance, 0);
        uint256 slpInTreasury = SLP.balanceOf(address(treasury));

        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(alice));
        governanceRedemptionPool.redeemToToken(alice, lgo.balanceOf(alice), address(WETH), 0);
        assertEq(SLP.balanceOf(alice), 0);
        assertEq(SLP.balanceOf(address(treasury)), slpInTreasury * 4 / 10);
        assertEq(alice.balance, (slpInTreasury) * 6 / 10);
        vm.stopPrank();

        vm.startPrank(bob);
        assertEq(bob.balance, 0);
        lgo.approve(address(governanceRedemptionPool), lgo.balanceOf(bob));
        governanceRedemptionPool.redeemToToken(bob, lgo.balanceOf(bob), address(WETH), 0);
        assertEq(bob.balance, (slpInTreasury) * 4 / 10);
        assertEq(SLP.balanceOf(address(treasury)), 0);
    }
}
