// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../interfaces/IETHUnwrapper.sol";
import {IBurnableERC20} from "../interfaces/IBurnableERC20.sol";

contract LvlStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;
    using SafeERC20 for IWETH;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    uint256 private constant ACC_REWARD_PRECISION = 1e12;
    uint256 public constant MAX_REWARD_PER_SECOND = 10 ether;
    uint256 public constant STAKING_TAX_PRECISION = 1000;
    uint8 public constant VERSION = 2;

    IBurnableERC20 public LVL;
    IERC20 public LLP;
    IWETH public WETH;

    IPool public pool;
    IETHUnwrapper public ethUnwrapper;

    uint256 public rewardsPerSecond;
    uint256 public lastUpdateRewardTime;
    uint256 public accRewardPerShare;
    address public controller;

    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) public withdrawableTokens;

    uint256 public stakingTax;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _pool, address _lvl, address _llp, address _weth, address _ethUnwrapper)
        external
        initializer
    {
        require(_pool != address(0), "LvlStaking:initialize: invalid address");
        require(_lvl != address(0), "LvlStaking:initialize: invalid address");
        require(_llp != address(0), "LvlStaking:initialize: invalid address");
        require(_weth != address(0), "LvlStaking::initialize: invalid address");
        require(_ethUnwrapper != address(0), "LvlStaking::initialize: invalid address");
        __Ownable_init();
        __ReentrancyGuard_init();
        pool = IPool(_pool);
        LVL = IBurnableERC20(_lvl);
        LLP = IERC20(_llp);
        WETH = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
    }

    function reinit_setStakingTax() external reinitializer(VERSION) {
        stakingTax = 4;
    }

    modifier onlyController() {
        require(msg.sender == controller, "onlyController");
        _;
    }

    // =============== VIEW FUNCTIONS ===============

    function pendingRewards(address _to) external view returns (uint256) {
        UserInfo memory user = userInfo[_to];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 totalStaked = LVL.balanceOf(address(this));
        if (block.timestamp > lastUpdateRewardTime && totalStaked != 0) {
            uint256 reward = (block.timestamp - lastUpdateRewardTime) * rewardsPerSecond;
            _accRewardPerShare += (reward * ACC_REWARD_PRECISION) / totalStaked;
        }
        return uint256(int256((user.amount * _accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt);
    }

    // =============== USER FUNCTIONS ===============

    function stake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "LvlStaking::stake: invalid amount");
        update();
        uint256 _taxAmount = _amount * stakingTax / STAKING_TAX_PRECISION;
        uint256 _stakedAmount = _amount - _taxAmount;

        UserInfo memory _userInfo = userInfo[_to];
        _userInfo.amount += _stakedAmount;
        _userInfo.rewardDebt += int256((_stakedAmount * accRewardPerShare) / ACC_REWARD_PRECISION);
        userInfo[_to] = _userInfo;

        LVL.safeTransferFrom(msg.sender, address(this), _amount);
        LVL.burn(_taxAmount);

        emit Staked(msg.sender, _to, _amount);
    }

    function unstake(address _to, uint256 _amount) external nonReentrant {
        address sender = msg.sender;
        UserInfo memory _userInfo = userInfo[sender];
        require(_userInfo.amount >= _amount, "LvlStaking::unstake: insufficient staked amount");
        update();
        _userInfo.amount -= _amount;
        _userInfo.rewardDebt -= int256((_amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        userInfo[sender] = _userInfo;
        LVL.safeTransfer(_to, _amount);
        emit Unstaked(sender, _to, _amount);
    }

    function claimRewards(address _to) external nonReentrant {
        require(_to != address(0), "LvlStaking::transferRewards: invalid address");
        update();
        address sender = msg.sender;
        UserInfo memory user = userInfo[sender];
        int256 accumulatedReward = int256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 rewards = uint256(accumulatedReward - user.rewardDebt);
        user.rewardDebt = accumulatedReward;
        userInfo[sender] = user;
        if (rewards != 0) {
            _safeTransferToken(address(LLP), _to, rewards);
            emit Claimed(sender, _to, rewards);
        }
    }

    function claimRewardsToSingleToken(address _to, address _tokenOut, uint256 _minAmountOut) external nonReentrant {
        require(_to != address(0), "LvlStaking::claimRewardsToSingleToken: invalid address");
        require(withdrawableTokens[_tokenOut], "LvlStaking::claimRewardsToSingleToken: !withdrawable");
        update();
        address sender = msg.sender;
        UserInfo memory user = userInfo[sender];
        int256 accumulatedReward = int256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 rewards = uint256(accumulatedReward - user.rewardDebt);
        user.rewardDebt = accumulatedReward;
        userInfo[sender] = user;
        if (rewards != 0) {
            uint256 amountOut = _swapRewardsToToken(_to, rewards, _tokenOut, _minAmountOut);
            emit SingleTokenClaimed(sender, _to, rewards, _tokenOut, amountOut);
        }
    }

    function update() public {
        uint256 _totalStakedAmount = LVL.balanceOf(address(this));
        if (block.timestamp > lastUpdateRewardTime) {
            uint256 reward = (block.timestamp - lastUpdateRewardTime) * rewardsPerSecond;
            accRewardPerShare =
                accRewardPerShare + (_totalStakedAmount == 0 ? 0 : (reward * ACC_REWARD_PRECISION) / _totalStakedAmount);
        }
        lastUpdateRewardTime = block.timestamp;
    }

    // ========== RESTRICTED FUNCTIONS ===============

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "LvlStaking::setController: invalid address");
        controller = _controller;
        emit ControllerSet(_controller);
    }

    function setTokenWithdrawable(address _token, bool _allowed) external onlyOwner {
        require(_token != address(LVL) && _token != address(0), "LvlStaking::setTokenWithdrawable: invalid address");
        if (withdrawableTokens[_token] != _allowed) {
            withdrawableTokens[_token] = _allowed;
            emit TokenWithdrawableSet(_token, _allowed);
        }
    }

    function setRewardsPerSecond(uint256 _rewardsPerSecond) external onlyController {
        require(_rewardsPerSecond <= MAX_REWARD_PER_SECOND, "LvlStaking::setRewardsPerSecond: > MAX_REWARD_PER_SECOND");
        update();
        rewardsPerSecond = _rewardsPerSecond;
        emit RewardsPerSecondSet(_rewardsPerSecond);
    }

    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyController
    {
        require(_tokenIn != address(LVL) && _tokenOut != _tokenIn, "LvlStaking::swap: invalid path");
        IERC20(_tokenIn).safeTransfer(address(pool), _amountIn);
        uint256 balanceBefore = IERC20(_tokenOut).balanceOf(address(this));
        pool.swap(_tokenIn, _tokenOut, _minAmountOut, address(this), abi.encode(msg.sender));
        uint256 actualAmountOut = IERC20(_tokenOut).balanceOf(address(this)) - balanceBefore;
        require(actualAmountOut >= _minAmountOut, "LvlStaking::swap: !slippage");
        emit Swap(_tokenIn, _tokenOut, _amountIn, actualAmountOut);
    }

    function convert(address _token, uint256 _amount, uint256 _minLlpAmount) external onlyController {
        require(_token != address(LVL) && _token != address(0), "LvlStaking::convertToLlp: invalid address");
        if (_amount > 0) {
            uint256 _balanceBefore = LLP.balanceOf(address(this));
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(address(LLP), _token, _amount, _minLlpAmount, address(this));
            uint256 _amountOut = LLP.balanceOf(address(this)) - _balanceBefore;
            require(_amountOut >= _minLlpAmount, "LvlStaking::convertToLlp: !slippage");
            emit RewardTokenConverted(_token, _amount, _amountOut);
        }
    }

    function recoverFund(address _token, address _to, uint256 _amount) external onlyOwner {
        require(_token != address(LVL) && _token != address(0), "LvlStaking::recoverFund: invalid token address");
        require(_to != address(0), "LvlStaking::recoverFund: invalid address");
        _safeTransferToken(_token, _to, _amount);
        emit FundRecovered(_to, _amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _swapRewardsToToken(address _to, uint256 _amount, address _tokenOut, uint256 _minAmountOut)
        internal
        returns (uint256)
    {
        LLP.safeIncreaseAllowance(address(pool), _amount);
        uint256 _balanceBefore = IERC20(_tokenOut).balanceOf(address(this));
        pool.removeLiquidity(address(LLP), _tokenOut, _amount, _minAmountOut, address(this));
        uint256 _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;
        require(_amountOut >= _minAmountOut, "LvlStaking::transferRewardsToSingleToken: !slippage");
        _safeTransferToken(_tokenOut, _to, _amountOut);
        return _amountOut;
    }

    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        if (_amount > 0) {
            if (_token == address(WETH)) {
                _safeUnwrapETH(_to, _amount);
            } else {
                IERC20(_token).safeTransfer(_to, _amount);
            }
        }
    }

    function _safeUnwrapETH(address _to, uint256 _amount) internal {
        WETH.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    /* ========== EVENTS ========== */
    event ControllerSet(address indexed _controller);
    event TokenWithdrawableSet(address indexed _token, bool _allowed);
    event RewardsPerSecondSet(uint256 _rewardsPerSecond);
    event FundRecovered(address indexed _to, uint256 _amount);
    event RewardTokenConverted(address indexed _fromToken, uint256 _fromAmount, uint256 _toAmount);
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event Staked(address indexed _from, address indexed _to, uint256 _amount);
    event Unstaked(address indexed _from, address indexed _to, uint256 _amount);
    event Claimed(address indexed _from, address indexed _to, uint256 _amount);
    event SingleTokenClaimed(
        address indexed _from, address indexed _to, uint256 _amount, address _tokenOut, uint256 _amountOut
    );
}
