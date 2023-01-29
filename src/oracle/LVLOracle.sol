// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {FixedPoint} from "../lib/FixedPoint.sol";
import {PairOracleTWAP, PairOracle} from "../lib/PairOracleTWAP.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";

contract LVLOracle is Initializable {
    using PairOracleTWAP for PairOracle;

    uint256 private constant PRECISION = 1e6;

    address public updater;
    uint256 public lastTWAP;

    PairOracle public lvlEthPair;
    PairOracle public ethBusdPair;

    function initialize(address _lvl, address _weth, address _lvlEthPair, address _ethBusdPair, address _updater)
        external
        initializer
    {
        require(_lvl != address(0), "LVLOracle::initialize: invalid address");
        require(_weth != address(0), "LVLOracle::initialize: invalid address");
        require(_lvlEthPair != address(0), "LVLOracle::initialize: invalid address");
        require(_ethBusdPair != address(0), "LVLOracle::initialize: invalid address");
        require(_updater != address(0), "LVLOracle::initialize: invalid address");
        lvlEthPair = PairOracle({
            pair: IUniswapV2Pair(_lvlEthPair),
            token: _lvl,
            priceAverage: FixedPoint.uq112x112(0),
            lastBlockTimestamp: 0,
            priceCumulativeLast: 0,
            lastTWAP: 0
        });
        ethBusdPair = PairOracle({
            pair: IUniswapV2Pair(_ethBusdPair),
            token: _weth,
            priceAverage: FixedPoint.uq112x112(0),
            lastBlockTimestamp: 0,
            priceCumulativeLast: 0,
            lastTWAP: 0
        });
        updater = _updater;
    }

    // =============== VIEW FUNCTIONS ===============

    function getCurrentTWAP() public view returns (uint256) {
        // round to 1e12
        return lvlEthPair.currentTWAP() * ethBusdPair.currentTWAP() / PairOracleTWAP.PRECISION / PRECISION;
    }

    // =============== USER FUNCTIONS ===============

    function update() external {
        require(msg.sender == updater, "LVLOracle::updatePrice: !updater");
        lvlEthPair.update();
        ethBusdPair.update();
        lastTWAP = lvlEthPair.lastTWAP * ethBusdPair.lastTWAP / PairOracleTWAP.PRECISION / PRECISION;
        emit PriceUpdated(block.timestamp, lastTWAP);
    }

    // ===============  EVENTS ===============
    event PriceUpdated(uint256 timestamp, uint256 price);
}
