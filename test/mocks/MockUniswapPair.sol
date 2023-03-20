// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockUniswapPair is ERC20 {
    address public token0;
    address public token1;
    uint32 blockTimestampLast;

    constructor(address _token0, address _token1) ERC20("Pair V2", "Pair V2") {
        token0 = _token0;
        token1 = _token1;
    }

    function updateBlockTimestampLast() external {
        blockTimestampLast = uint32(block.timestamp);
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 _blockTimestampLast) {
        reserve0 = 1 ether;
        reserve1 = 1 ether;
        _blockTimestampLast = blockTimestampLast;
    }

    function price0CumulativeLast() external view returns (uint256) {
        return 1e18;
    }

    function price1CumulativeLast() external view returns (uint256) {
        return 1e18;
    }

    function mintTo(uint256 _amount, address _to) public {
        _mint(_to, _amount);
    }
}
