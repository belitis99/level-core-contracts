// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {DutchAuction} from "./DutchAuction.sol";

interface IBurnableERC20 is IERC20 {
    function burn(uint256 _amount) external;
}

contract LgoDutchAuction is DutchAuction {
    constructor(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _startPrice,
        uint128 _minimumPrice,
        address _admin,
        address _treasury
    )
        DutchAuction(
            _auctionToken,
            _payToken,
            _totalTokens,
            _startTime,
            _endTime,
            _startPrice,
            _minimumPrice,
            _admin,
            _treasury
        )
    {}

    function _finalizeSuccessfulAuctionFund() internal override {
        IBurnableERC20(payToken).burn(commitmentsTotal);
    }
}
