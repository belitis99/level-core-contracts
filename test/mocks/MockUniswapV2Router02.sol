// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

contract MockUniswapV2Router02 {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        ERC20(token1).transfer(msg.sender, amountOutMin);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOutMin;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        ERC20(token0).transferFrom(msg.sender, address(this), amountIn);
        ERC20(token1).transfer(msg.sender, amountOutMin);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountTokenA,
        uint256 amountTokenB,
        uint256 minAmountTokenA,
        uint256 minAmountTokenB,
        address to,
        uint256 deadline
    ) external returns (uint256 _tokenAInLp, uint256 _tokenBInlp, uint256 _lp) {
        ERC20(tokenA).transferFrom(msg.sender, address(this), amountTokenA);
        ERC20(tokenB).transferFrom(msg.sender, address(this), amountTokenB);
        _tokenAInLp = 0;
        _tokenBInlp = 0;
        _lp = 0;
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        amountToken = amountTokenMin;
        amountETH = amountETHMin;
        liquidity = amountTokenDesired * 1e18;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}
}
