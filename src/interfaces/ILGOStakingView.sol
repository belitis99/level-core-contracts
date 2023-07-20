// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

interface ILGOStakingView {
    function estimatedLGOCirculatingSupply() external view returns (uint256 _balance);
    function addAuctionedAmount(uint256 _amount) external;
    function addEmission(uint256 _rewardsPerSecond, uint256 _startTimestamp, uint256 _endTimestamp) external;
}
