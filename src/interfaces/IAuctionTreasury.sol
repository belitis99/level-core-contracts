// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

interface IAuctionTreasury {
    function transferLVL(address _to, uint256 _amount) external;
    function transferLGO(address _to, uint256 _amount) external;
    function distribute() external;
}
