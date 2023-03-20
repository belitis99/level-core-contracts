// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ERC20Burnable} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

/// @title LP Token
/// @author YAPP
/// @notice User will receive LP Token when deposit their token to protocol; and it can be redeem to receive
/// any token of their choice
contract LPToken is ERC20Burnable {
    address public minter;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        minter = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "LPToken: !minter");
        _mint(to, amount);
    }
}
