pragma solidity >=0.8.0;

import {IERC20, SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract MockLevelMaster {
    using SafeERC20 for IERC20;
    IERC20[] public lpToken;

    function deposit(
        uint256 pid,
        uint256 amount,
        address /* to */
    ) public {
        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);
    }

    function addPool(address token) external {
        lpToken.push(IERC20(token));
    }
}
