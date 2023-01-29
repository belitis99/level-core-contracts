// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IPool} from "../interfaces/IPool.sol";

contract Treasury is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    IPool public pool;
    address[] public feeTokens;

    /**
     * @dev Called by the proxy contract
     *
     */
    function initialize(address _pool) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        require(_pool != address(0), "Treasury::initialize: zero address");
        pool = IPool(_pool);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function updateFeeTokens(address[] memory _feeTokens) external onlyRole(CONTROLLER_ROLE) {
        feeTokens = _feeTokens;

        emit FeeTokensUpdated();
    }

    function withdrawFee() external onlyRole(CONTROLLER_ROLE) {
        for (uint256 i = 0; i < feeTokens.length;) {
            address _token = feeTokens[i];
            (uint256 _feeReserve,,,,) = pool.poolTokens(_token);
            if (_feeReserve > 0) {
                pool.withdrawFee(_token, address(this));
            }
            unchecked {
                ++i;
            }
        }

        emit FeeWithdrawn();
    }

    function transfer(address _token, address _receiver, uint256 _amount) external onlyRole(SPENDER_ROLE) {
        address spender = _msgSender();
        IERC20(_token).safeTransfer(_receiver, _amount);

        emit Transfer(spender, _token, _receiver, _amount);
    }

    function transferETH(address _receiver, uint256 _amount) external onlyRole(SPENDER_ROLE) nonReentrant {
        address spender = _msgSender();
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = _receiver.call{value: _amount}(new bytes(0));
        require(success, "Treasury::transferETH: ETH transfer failed");

        emit TransferETH(spender, _receiver, _amount);
    }

    receive() external payable {}

    /* ========== EVENTS ========== */
    event FeeTokensUpdated();
    event FeeWithdrawn();
    event Transfer(address indexed _spender, address _token, address _receiver, uint256 _amount);
    event TransferETH(address indexed _spender, address _receiver, uint256 _amount);
}
