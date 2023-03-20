// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../interfaces/IETHUnwrapper.sol";

contract Treasury is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    uint256 public constant RATIO_PRECISION = 100;
    uint8 public constant VERSION = 4;

    IPool public pool;

    // begin: deprecated vars
    address[] public feeTokens;
    uint256 public devReserveRatio;
    address public devReserve;
    // end: deprecated vars

    // ===== begin: V3 Storage ====
    IWETH public weth;
    IETHUnwrapper public ethUnwrapper;
    address public lgoRedemptionPool;
    address public LLP;
    mapping(address => bool) public withdrawableTokens;
    // ===== end: V3 Storage ====

    // ===== begin: V4 Storage ====
    address public lvlUsdtLP;
    // ===== end: V4 Storage ====

    modifier onlyLgoRedemptionPool() {
        require(msg.sender == lgoRedemptionPool, "Treasury::only LGO redemption pool");
        _;
    }

    function initialize(address _pool) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        require(_pool != address(0), "Treasury::initialize: zero address");
        pool = IPool(_pool);
    }

    function reinit_v3(address _weth, address _ethUnwrapper, address _llp) external reinitializer(3) {
        require(_weth != address(0), "Treasury::invalid address");
        require(_ethUnwrapper != address(0), "Treasury::invalid address");
        require(_llp != address(0), "Treasury::invalid address");
        weth = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
        LLP = _llp;
    }

    function reinit_v4(address _lvlUsdtLP) external reinitializer(VERSION) {
        require(_lvlUsdtLP != address(0), "Treasury::invalid address");
        lvlUsdtLP = _lvlUsdtLP;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function distribute(address _token, address _receiver, uint256 _amount) external onlyLgoRedemptionPool {
        require(_token != address(0), "Treasury::invalid token address");
        require(_token == address(LLP) || _token == address(lvlUsdtLP), "Treasury::token not allowed");
        require(_receiver != address(0), "Treasury::invalid receiver address");
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit TokenDistributed(lgoRedemptionPool, _token, _receiver, _amount);
    }

    function convertLLPToToken(address _receiver, address _tokenOut, uint256 _lpAmount, uint256 _minAmountOut)
        external
        onlyLgoRedemptionPool
    {
        require(LLP != address(0), "Treasury::llp not set");
        require(_receiver != address(0), "Treasury::invalid receiver address");
        uint256 actualAmountOut;
        if (_tokenOut == address(weth)) {
            actualAmountOut = _removeLiquidity(LLP, _tokenOut, _lpAmount, _minAmountOut, address(this));
            _safeUnwrapETH(actualAmountOut, _receiver);
        } else {
            actualAmountOut = _removeLiquidity(LLP, _tokenOut, _lpAmount, _minAmountOut, _receiver);
        }
        emit TokenDistributed(lgoRedemptionPool, _tokenOut, _receiver, actualAmountOut);
    }

    function convertToLLP(address _token, uint256 _amount, uint256 _minAmountOut)
        external
        nonReentrant
        onlyRole(CONTROLLER_ROLE)
    {
        uint256 amountOut = _addLiquidity(_token, _amount, LLP, _minAmountOut, address(this));
        emit LLPConverted(_token, address(LLP), _amount, amountOut);
    }

    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        require(_toToken != _fromToken, "invalidPath");
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        uint256 balanceBefore = IERC20(_toToken).balanceOf(address(this));
        pool.swap(_fromToken, _toToken, _minAmountOut, address(this), abi.encode(msg.sender));
        uint256 actualAmountOut = IERC20(_toToken).balanceOf(address(this)) - balanceBefore;
        require(actualAmountOut >= _minAmountOut, ">slippage");
        emit Swap(_fromToken, _toToken, _amountIn, actualAmountOut);
    }

    /* ========== RESTRICTED ========== */

    function setLgoRedemptionPool(address _lgoRedemptionPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lgoRedemptionPool != address(0), "Treasury::invalid token address");
        lgoRedemptionPool = _lgoRedemptionPool;
        emit LgoRedemptionPoolSet(_lgoRedemptionPool);
    }

    function setLLPToken(address _llp) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_llp != address(0), "Treasury::invalid token address");
        LLP = _llp;
        emit LLPTokenSet(_llp);
    }

    function addWithdrawableToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "Treasury::invalid token address");
        require(!withdrawableTokens[_token], "Treasury::token already allowed");
        withdrawableTokens[_token] = true;
        emit WithdrawableTokenAdded(_token);
    }

    function removeWithdrawableToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "Treasury::invalid token address");
        require(withdrawableTokens[_token], "Treasury::token not allowed");
        withdrawableTokens[_token] = false;
        emit WithdrawableTokenRemoved(_token);
    }

    function recoverFund(address _token, address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), "Treasury::recoverFund: invalid address");
        require(_token != address(0), "Treasury::recoverFund: invalid address");
        IERC20(_token).safeTransfer(_to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    /* ========== INTERNAL FUNCTION ========== */

    function _addLiquidity(address _token, uint256 _amount, address _llp, uint256 _minAmountOut, address _to)
        internal
        returns (uint256 actualLPAmountOut)
    {
        uint256 lpBalanceBefore = IERC20(_llp).balanceOf(_to);
        IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
        pool.addLiquidity(_llp, _token, _amount, _minAmountOut, _to);
        actualLPAmountOut = IERC20(_llp).balanceOf(_to) - lpBalanceBefore;
    }

    function _removeLiquidity(
        address _llp,
        address _tokenOut,
        uint256 _lpAmount,
        uint256 _minAmountOut,
        address _receiver
    ) internal returns (uint256 actualAmountOut) {
        require(withdrawableTokens[_tokenOut], "Treasury::token not withdrawable");
        uint256 outTokenBalanceBefore = IERC20(_tokenOut).balanceOf(_receiver);
        IERC20(_llp).safeIncreaseAllowance(address(pool), _lpAmount);
        // we will calculate amount out ourself, so skip slippage check on pool
        pool.removeLiquidity(LLP, _tokenOut, _lpAmount, 0, _receiver);
        actualAmountOut = IERC20(_tokenOut).balanceOf(_receiver) - outTokenBalanceBefore;
        require(actualAmountOut >= _minAmountOut, "Treasury::<minAmountOut");
    }

    function _safeUnwrapETH(uint256 _amount, address _to) internal {
        weth.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    /* ========== EVENTS ========== */
    event LLPConverted(address indexed token, address indexed llp, uint256 amount, uint256 lpAmountOut);
    event TokenDistributed(address indexed spender, address token, address receiver, uint256 amount);
    event LLPTokenSet(address indexed token);
    event LgoRedemptionPoolSet(address indexed token);
    event WithdrawableTokenAdded(address indexed token);
    event WithdrawableTokenRemoved(address indexed token);
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
}
