// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

interface IAuctionFactory {
    function totalAuctions() external view returns (uint256);
    function auctions(uint256 _index) external view returns (address);
}
