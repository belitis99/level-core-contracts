// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../interfaces/IETHUnwrapper.sol";

contract LlpRewardDistributor is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    uint256 public constant MAX_REWARD_PER_SECOND = 10 ether;
    IWETH public weth;
    IERC20 public rewardToken;
    IPool public pool;
    IETHUnwrapper public ethUnwrapper;

    uint256 public rewardsPerSecond;
    address public requester;
    address public controller;

    mapping(address => bool) public withdrawableTokens;

    modifier onlyRequester() {
        require(msg.sender == requester, "onlyRequester");
        _;
    }

    modifier onlyController() {
        require(msg.sender == controller, "onlyController");
        _;
    }

    function initialize(address _pool, address _rewardToken, address _weth, address _ethUnwrapper)
        external
        initializer
    {
        require(_rewardToken != address(0), "LlpRewardDistributor::initialize: Invalid address");
        require(_pool != address(0), "LlpRewardDistributor::initialize: Invalid address");
        require(_weth != address(0), "LlpRewardDistributor::initialize: Invalid address");
        require(_ethUnwrapper != address(0), "LlpRewardDistributor::initialize: Invalid address");
        __Ownable_init();
        pool = IPool(_pool);
        rewardToken = IERC20(_rewardToken);
        weth = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
    }

    // =============== MUTATIVE FUNCTIONS ===============

    function transferRewards(address _to, uint256 _amount) external onlyRequester {
        require(_to != address(0), "LlpRewardDistributor::transferRewards: Invalid address");
        _safeTransferToken(address(rewardToken), _to, _amount);
        emit RewardTransferred(_to, address(rewardToken), _amount);
    }

    function transferRewardsToSingleToken(address _to, uint256 _amount, address _tokenOut, uint256 _minAmountOut)
        external
        onlyRequester
    {
        require(_to != address(0), "LlpRewardDistributor::transferRewardsToSingleToken:invalidAddress");
        require(withdrawableTokens[_tokenOut], "LlpRewardDistributor::transferRewardsToSingleToken:notWithdrawable");
        if (_amount > 0) {
            rewardToken.safeIncreaseAllowance(address(pool), _amount);
            uint256 _balanceBefore = IERC20(_tokenOut).balanceOf(address(this));
            pool.removeLiquidity(address(rewardToken), _tokenOut, _amount, _minAmountOut, address(this));
            uint256 _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;
            require(_amountOut >= _minAmountOut, "LlpRewardDistributor::transferRewardsToSingleToken:slippage");
            _safeTransferToken(_tokenOut, _to, _amountOut);
            emit RewardTransferred(_to, _tokenOut, _amountOut);
        }
    }

    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyController
    {
        require(_toToken != _fromToken, "invalidPath");
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        uint256 balanceBefore = IERC20(_toToken).balanceOf(address(this));
        pool.swap(_fromToken, _toToken, _minAmountOut, address(this), abi.encode(msg.sender));
        uint256 actualAmountOut = IERC20(_toToken).balanceOf(address(this)) - balanceBefore;
        require(actualAmountOut >= _minAmountOut, ">slippage");
        emit Swap(_fromToken, _toToken, _amountIn, actualAmountOut);
    }

    // =============== RESTRICTED FUNCTIONS ===============

    function convertToLlp(address _token, uint256 _amount, uint256 _minLlpAmount) external onlyController {
        require(_token != address(0), "LlpRewardDistributor::convertToLlp: Invalid address");
        if (_amount > 0) {
            uint256 _balanceBefore = rewardToken.balanceOf(address(this));
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(address(rewardToken), _token, _amount, _minLlpAmount, address(this));
            uint256 _amountOut = rewardToken.balanceOf(address(this)) - _balanceBefore;
            require(_amountOut >= _minLlpAmount, "LlpRewardDistributor::convertToLlp: slippage");
            emit RewardTokenConverted(_token, _amount, _amountOut);
        }
    }

    function setRewardsPerSecond(uint256 _rewardsPerSecond) external onlyController {
        require(_rewardsPerSecond <= MAX_REWARD_PER_SECOND, "> MAX_REWARD_PER_SECOND");
        rewardsPerSecond = _rewardsPerSecond;
        emit RewardsPerSecondUpdated(_rewardsPerSecond);
    }

    function setRequester(address _requester) external onlyOwner {
        require(_requester != address(0), "LlpRewardDistributor::setRequester: Invalid address");
        requester = _requester;
        emit RequesterSet(_requester);
    }

    function recoverFund(address _token, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "LlpRewardDistributor::recoverFund: Invalid address");
        require(_token != address(0), "LlpRewardDistributor::recoverFund: Invalid address");
        _safeTransferToken(_token, _to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    function recoverETH(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "LlpRewardDistributor::recoverETH: Invalid address");
        (bool success,) = _to.call{value: _amount}(new bytes(0));
        require(success, "LlpRewardDistributor::recoverETH: ETH transfer failed");
        emit EthRecovered(_to, _amount);
    }

    function setTokenWithdrawable(address _token, bool _allowed) external onlyOwner {
        require(_token != address(0), "LlpRewardDistributor::setTokenWithdrawable: Invalid address");
        if (withdrawableTokens[_token] != _allowed) {
            withdrawableTokens[_token] = _allowed;
            emit SetTokenWithdrawable(_token, _allowed);
        }
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "LlpRewardDistributor::setController: Invalid address");
        controller = _controller;
        emit ControllerSet(_controller);
    }

    // =============== INTERNAL ===============
    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        if (_amount > 0) {
            if (_token == address(weth)) {
                _safeUnwrapETH(_to, _amount);
            } else {
                IERC20(_token).safeTransfer(_to, _amount);
            }
        }
    }

    function _safeUnwrapETH(address _to, uint256 _amount) internal {
        weth.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    // =============== EVENTS ===============

    event RewardsPerSecondUpdated(uint256 _rewardsPerSecond);
    event RewardTransferred(address indexed _to, address indexed _token, uint256 _amount);
    event RequesterSet(address indexed _lgoStaking);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
    event EthRecovered(address _to, uint256 _amount);
    event SetTokenWithdrawable(address indexed _token, bool _allowed);
    event RewardTokenConverted(address indexed _fromToken, uint256 _fromAmount, uint256 _toAmount);
    event ControllerSet(address indexed _controller);
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
}
