// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {LgoDutchAuction} from "./LgoDutchAuction.sol";
import {IAuctionTreasury} from "../interfaces/IAuctionTreasury.sol";

contract LgoAuctionFactory is Ownable {
    using SafeERC20 for IERC20;

    uint64 public constant MIN_AUCTION_DURATION = 0.5 days;
    uint64 public constant MAX_AUCTION_DURATION = 10 days;
    address public immutable LGO;
    address public immutable LVL;
    address public treasury;
    address public admin;
    address[] public auctions;

    constructor(address _lgo, address _lvl, address _treasury, address _admin) {
        LGO = _lgo;
        LVL = _lvl;
        setTreasury(_treasury);
        setAdmin(_admin);
    }

    /*===================== VIEWS =====================*/
    function totalAuctions() public view returns (uint256) {
        return auctions.length;
    }

    function createAuction(
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _startPrice,
        uint128 _minPrice
    ) external onlyOwner {
        require(_endTime - _startTime >= MIN_AUCTION_DURATION, "< MIN_AUCTION_DURATION");
        require(_endTime - _startTime <= MAX_AUCTION_DURATION, "> MAX_AUCTION_DURATION");

        LgoDutchAuction _newAuction = new LgoDutchAuction(
            LGO,
            LVL,
            _totalTokens,
            _startTime,
            _endTime,
            _startPrice,
            _minPrice,
            admin,
            treasury);
        IAuctionTreasury(treasury).transferLGO(address(_newAuction), _totalTokens);
        auctions.push(address(_newAuction));

        emit AuctionCreated(LGO, LVL, _totalTokens, _startTime, _endTime, _startPrice, _minPrice, admin, treasury);
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AuctionAdminUpdated(_admin);
    }

    // EVENTS
    event AuctionCreated(
        address indexed _auctionToken,
        address indexed _payToken,
        uint256 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint256 _startPrice,
        uint256 _minPrice,
        address auctionAdmin,
        address auctionTreasury
    );
    event AuctionAdminUpdated(address indexed _address);
    event AuctionTreasuryUpdated(address indexed _address);
}
