pragma solidity >=0.8.0;

import {IERC20, SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "./MockERC20.sol";

struct PoolTokenInfo {
    /// @notice amount reserved for fee
    uint256 feeReserve;
    /// @notice recorded balance of token in pool
    uint256 poolBalance;
    /// @notice last borrow index update timestamp
    uint256 lastAccrualTimestamp;
    /// @notice accumulated interest rate
    uint256 borrowIndex;
    /// @notice average entry price of all short position
    uint256 averageShortPrice;
}

contract MockPool {
    using SafeERC20 for IERC20;

    MockERC20 public lpToken;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => PoolTokenInfo) public poolTokens;

    constructor() {
        lpToken = new MockERC20("LP", "LP", 18);
    }

    function addLiquidity(
        address, /* _tranche */
        address _token,
        uint256 _amount,
        uint256, /* _minLpAmount */
        address _to
    ) external payable {
        if (_token != ETH) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        lpToken.mintTo(_amount, _to);
    }

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to)
        external
    {
        IERC20(_tranche).safeTransferFrom(msg.sender, address(this), _lpAmount);
        IERC20(_tokenOut).safeTransfer(_to, _lpAmount);
    }

    function withdrawFee(address _token, address _recipient) external {
        uint256 amount = poolTokens[_token].feeReserve;
        poolTokens[_token].feeReserve = 0;
        IERC20(_token).transfer(_recipient, amount);
    }

    function setFeeReserve(address _token, uint256 amount) external {
        poolTokens[_token].feeReserve = amount;
    }

    function setPoolBalance(address _token, uint256 amount) external {
        poolTokens[_token].poolBalance = amount;
    }

    function swap(address _tokenIn, address _tokenOut, uint256, address _to, bytes calldata) external {
        uint256 outAmount = IERC20(_tokenIn).balanceOf(address(this)) - poolTokens[_tokenIn].poolBalance;
        IERC20(_tokenOut).safeTransfer(_to, outAmount);
        poolTokens[_tokenIn].poolBalance += outAmount;
        if (poolTokens[_tokenOut].poolBalance > outAmount) {
            poolTokens[_tokenOut].poolBalance -= outAmount;
        } else {
            poolTokens[_tokenOut].poolBalance = 0;
        }
    }

    function setLpToken(address _lpToken) external {
        lpToken = MockERC20(_lpToken);
    }
}
