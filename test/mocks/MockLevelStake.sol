//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract MockLevelStake {
    uint256 totalAmount;

    using SafeERC20 for IERC20;

    IERC20 public immutable LVL;

    constructor(address _lvl) {
        LVL = IERC20(_lvl);
    }

    function stake(address _to, uint256 _amount) external {
        LVL.safeTransferFrom(msg.sender, address(this), _amount);
        totalAmount += _amount;
    }
}
