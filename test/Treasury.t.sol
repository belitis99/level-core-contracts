pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "src/treasury/Treasury.sol";
import "./mocks/MockPool.sol";
import "./mocks/MockLpToken.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";

contract TreasuryTest is Test {
    address admin = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address controller = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address redemption = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address spender = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;

    Treasury treasury;
    MockPool pool;

    WETH9 public WETH;
    ETHUnwrapper ethUnwrapper;

    MockERC20 USDT;
    MockERC20 BTC;
    LPToken LLP;

    function setUp() external {
        vm.startPrank(admin);
        pool = new MockPool();

        USDT = new MockERC20("USDT", "USDT", 18);
        BTC = new MockERC20("BTC", "BTC", 18);
        WETH = new WETH9();
        LLP = LPToken(address(pool.lpToken()));

        USDT.mintTo(1 ether, admin);
        BTC.mintTo(1 ether, admin);

        ethUnwrapper = new ETHUnwrapper(address(WETH));

        treasury = new Treasury();
        treasury.initialize(address(pool));
        treasury.reinit_v3(address(WETH), address(ethUnwrapper), address(LLP));

        vm.deal(admin, 2 ether);
        WETH.deposit{value: 2 ether}();
        WETH.transfer(address(treasury), 1 ether);
        WETH.transfer(address(pool), 1 ether);
        BTC.mintTo(1 ether, address(treasury));
        USDT.mintTo(1 ether, address(treasury));

        BTC.approve(address(pool), 1 ether);
        pool.addLiquidity(address(0), address(BTC), 1 ether, 0, address(treasury));

        bytes32 adminRole = treasury.DEFAULT_ADMIN_ROLE();
        treasury.grantRole(adminRole, controller);

        bytes32 controllerRole = treasury.CONTROLLER_ROLE();
        treasury.grantRole(controllerRole, controller);
        vm.stopPrank();
    }

    function test_add_and_remove_withdrawable_token() external {
        vm.startPrank(spender);
        vm.expectRevert();
        treasury.addWithdrawableToken(address(BTC));
        vm.stopPrank();

        vm.startPrank(controller);
        vm.expectRevert("Treasury::invalid token address");
        treasury.addWithdrawableToken(address(0));
        treasury.addWithdrawableToken(address(BTC));
        vm.expectRevert("Treasury::token already allowed");
        treasury.addWithdrawableToken(address(BTC));
        vm.expectRevert("Treasury::invalid token address");
        treasury.removeWithdrawableToken(address(0));
        treasury.removeWithdrawableToken(address(BTC));
        vm.expectRevert("Treasury::token not allowed");
        treasury.removeWithdrawableToken(address(BTC));
        vm.stopPrank();
    }

    function test_control_controller() external {
        bytes32 controllerRole = treasury.CONTROLLER_ROLE();

        // revert grant controller !admin
        vm.startPrank(spender);
        vm.expectRevert();
        treasury.grantRole(controllerRole, controller);
        vm.stopPrank();

        // success grant controller
        vm.startPrank(admin);
        treasury.grantRole(controllerRole, controller);
        assertEq(treasury.hasRole(controllerRole, controller), true);

        // success revoke controller
        treasury.revokeRole(controllerRole, controller);
        assertFalse(treasury.hasRole(controllerRole, controller));
        vm.stopPrank();
    }

    function test_convert_to_llp() external {
        vm.startPrank(controller);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        treasury.convertToLLP(address(BTC), 1000 ether, 1 ether);
        treasury.convertToLLP(address(BTC), 1 ether, 1 ether);
        vm.stopPrank();
    }

    function test_distribute() external {
        vm.startPrank(controller);
        assertEq(LLP.balanceOf(redemption), 0);
        vm.expectRevert("Treasury::only LGO redemption pool");
        treasury.distribute(address(LLP), redemption, 1 ether);
        treasury.setLgoRedemptionPool(redemption);
        vm.stopPrank();

        vm.startPrank(redemption);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        treasury.distribute(address(LLP), redemption, 2 ether);
        treasury.distribute(address(LLP), redemption, 1 ether);
        assertEq(LLP.balanceOf(redemption), 1 ether);
    }

    function test_distribute_to_token() external {
        vm.startPrank(controller);
        assertEq(LLP.balanceOf(redemption), 0);
        vm.expectRevert("Treasury::only LGO redemption pool");
        treasury.convertLLPToToken(redemption, address(BTC), 1 ether, 1 ether);
        treasury.setLgoRedemptionPool(redemption);
        vm.stopPrank();

        vm.startPrank(redemption);
        vm.expectRevert("Treasury::token not withdrawable");
        treasury.convertLLPToToken(redemption, address(BTC), 1 ether, 2 ether);
        vm.stopPrank();

        vm.startPrank(controller);
        treasury.addWithdrawableToken(address(BTC));
        vm.stopPrank();

        vm.startPrank(redemption);
        vm.expectRevert("Treasury::<minAmountOut");
        treasury.convertLLPToToken(redemption, address(BTC), 1 ether, 2 ether);
        treasury.convertLLPToToken(redemption, address(BTC), 1 ether, 1 ether);
        assertEq(LLP.balanceOf(redemption), 0 ether);
        assertEq(BTC.balanceOf(redemption), 1 ether);
        vm.stopPrank();
    }

    function test_distribute_to_native_token() external {
        vm.startPrank(controller);
        assertEq(LLP.balanceOf(redemption), 0);
        vm.expectRevert("Treasury::only LGO redemption pool");
        treasury.convertLLPToToken(redemption, address(WETH), 1 ether, 1 ether);
        treasury.setLgoRedemptionPool(redemption);
        vm.stopPrank();

        vm.startPrank(redemption);
        vm.expectRevert("Treasury::token not withdrawable");
        treasury.convertLLPToToken(redemption, address(WETH), 1 ether, 2 ether);
        vm.stopPrank();

        vm.startPrank(controller);
        treasury.addWithdrawableToken(address(WETH));
        vm.stopPrank();

        vm.startPrank(redemption);
        vm.expectRevert("Treasury::<minAmountOut");
        treasury.convertLLPToToken(redemption, address(WETH), 1 ether, 2 ether);
        treasury.convertLLPToToken(redemption, address(WETH), 1 ether, 1 ether);
        assertEq(LLP.balanceOf(redemption), 0 ether);
        assertEq(redemption.balance, 1 ether);
        vm.stopPrank();
    }

    function test_recover_fund() external {
        // not admin => revert
        USDT.mintTo(1000 ether, address(treasury));
        vm.startPrank(spender);
        vm.expectRevert();
        treasury.recoverFund(address(USDT), admin, 10 ether);
        vm.stopPrank();

        vm.startPrank(admin);

        // invalid address, revert
        vm.expectRevert();
        treasury.recoverFund(address(0), admin, 10 ether);

        vm.expectRevert();
        treasury.recoverFund(address(USDT), address(0), 10 ether);

        // success
        treasury.recoverFund(address(USDT), admin, 10 ether);
        vm.stopPrank();
    }

    function test_set_l_lp() external {
        // not admin => revert
        vm.startPrank(spender);
        vm.expectRevert();
        treasury.setLLPToken(address(LLP));
        vm.stopPrank();

        vm.startPrank(admin);

        // invalid address, revert
        vm.expectRevert();
        treasury.setLLPToken(address(0));

        // success
        treasury.setLLPToken(address(LLP));
        vm.stopPrank();
    }
}
