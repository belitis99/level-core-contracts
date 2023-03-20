pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

contract ETHUnwrapper {
    using SafeERC20 for IWETH;

    IWETH private immutable weth;

    constructor(address _weth) {
        require(_weth != address(0), "Invalid weth address");
        weth = IWETH(_weth);
    }

    function unwrap(uint256 _amount, address _to) external {
        weth.safeTransferFrom(msg.sender, address(this), _amount);
        weth.withdraw(_amount);
        // transfer out all ETH, include amount tranfered in by accident. We don't want ETH to stuck here forever
        _safeTransferETH(_to, address(this).balance);
    }

    function _safeTransferETH(address _to, uint256 _amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = _to.call{value: _amount}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    receive() external payable {}
}
