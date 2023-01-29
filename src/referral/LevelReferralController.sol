// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ILevelReferralRegistry} from "../interfaces/ILevelReferralRegistry.sol";
import {ILVLOracle} from "../interfaces/ILVLOracle.sol";
import {ILevelStake} from "../interfaces/ILevelStake.sol";

contract LevelReferralController is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        uint256 TWAP;
        uint256 allocationTime;
    }

    struct UserInfo {
        uint256 tradingPoint;
        uint256 referralPoint;
        uint256 claimed;
    }

    struct TierInfo {
        uint256 minTrader;
        uint256 minEpochReferralPoint;
        uint256 discountForTrader;
        uint256 rebateForReferrer;
    }

    uint256 private constant PRECISION = 1e6;
    uint256 public constant MIN_EPOCH_DURATION = 7 days;

    IERC20 public LVL;
    ILVLOracle public oracle;
    ILevelReferralRegistry public referralRegistry;

    TierInfo[] public tiers;
    /// @dev epoch -> epochInfo
    mapping(uint256 => EpochInfo) public epochs;
    /// @dev epoch -> user -> userInfo
    mapping(uint256 => mapping(address => UserInfo)) public users;

    address public updater;
    address public distributor;

    uint256 public currentEpoch;
    uint256 public lastEpochTimestamp;
    uint256 public epochDuration;

    ILevelStake public levelStake;
    bool public enableStaking;

    function initialize(
        address _lvl,
        address _oracle,
        address _levelRegistry,
        address _levelStake,
        bool _enableStaking,
        uint256 _startTime
    ) external initializer {
        require(_lvl != address(0), "LevelReferralController::initialize: invalid address");
        require(_oracle != address(0), "LevelReferralController::initialize: invalid address");
        require(_levelRegistry != address(0), "LevelReferralController::initialize: invalid address");
        require(_startTime >= block.timestamp, "LevelReferralController::initialize: invalid start time");
        __Ownable_init();
        LVL = IERC20(_lvl);
        oracle = ILVLOracle(_oracle);
        referralRegistry = ILevelReferralRegistry(_levelRegistry);
        levelStake = ILevelStake(_levelStake);
        epochDuration = MIN_EPOCH_DURATION;
        enableStaking = _enableStaking;
        lastEpochTimestamp = _startTime;
        oracle.update();

        tiers.push(TierInfo({minTrader: 0, minEpochReferralPoint: 0, discountForTrader: 0, rebateForReferrer: 0}));
        tiers.push(
            TierInfo({minTrader: 5, minEpochReferralPoint: 2_000e30, discountForTrader: 5e4, rebateForReferrer: 5e4})
        );
        tiers.push(
            TierInfo({minTrader: 15, minEpochReferralPoint: 10_000e30, discountForTrader: 10e4, rebateForReferrer: 10e4})
        );
        tiers.push(
            TierInfo({minTrader: 30, minEpochReferralPoint: 50_000e30, discountForTrader: 10e4, rebateForReferrer: 15e4})
        );
    }

    // =============== VIEW FUNCTIONS ===============

    function getNextEpoch() public view returns (uint256) {
        return lastEpochTimestamp + epochDuration;
    }

    function getUserTier(uint256 _epoch, address _user) public view returns (uint256) {
        if (_user == address(0)) {
            return 0;
        }
        UserInfo memory user = users[_epoch][_user];
        uint256 currentTier;

        for (; currentTier < tiers.length - 1;) {
            TierInfo memory _nextTierInfo = tiers[currentTier + 1];
            if (
                referralRegistry.referredCount(_user) < _nextTierInfo.minTrader
                    || user.referralPoint < _nextTierInfo.minEpochReferralPoint
            ) {
                break;
            }

            unchecked {
                ++currentTier;
            }
        }

        return currentTier;
    }

    function claimable(uint256 _epoch, address _user) public view returns (uint256) {
        EpochInfo memory epoch = epochs[_epoch];

        if (epoch.TWAP == 0) {
            return 0;
        }

        UserInfo memory user = users[_epoch][_user];
        uint256 userTier = getUserTier(_epoch, _user);
        uint256 referrerTier = getUserTier(_epoch, referralRegistry.referredBy(_user));

        uint256 rewardForTrading = user.tradingPoint * tiers[referrerTier].discountForTrader / PRECISION;
        uint256 rewardForReferral = user.referralPoint * tiers[userTier].rebateForReferrer / PRECISION;

        return (rewardForTrading + rewardForReferral) / epoch.TWAP - user.claimed;
    }

    // =============== USER FUNCTIONS ===============

    function setReferrer(address _referrer) external {
        referralRegistry.setReferrer(msg.sender, _referrer);

        emit ReferrerSet(msg.sender, _referrer);
    }

    function updatePoint(address _trader, uint256 _point) external {
        require(msg.sender == updater, "LevelReferralController::updatePoint: !updater");
        require(_trader != address(0), "LevelReferralController::updatePoint: invalid address");
        address referrer = referralRegistry.referredBy(_trader);
        if (referrer == address(0) || _point == 0) {
            return;
        }

        users[currentEpoch][_trader].tradingPoint += _point;
        users[currentEpoch][referrer].referralPoint += _point;

        emit TradingPointUpdated(currentEpoch, _trader, _point);
        emit ReferralPointUpdated(currentEpoch, referrer, _trader, _point);
    }

    function claim(uint256 _epoch, address _to) external {
        require(_epoch < currentEpoch, "LevelReferralController::claim: !epoch");
        uint256 reward = claimable(_epoch, msg.sender);
        require(reward != 0, "LevelReferralController::claim: !reward");

        UserInfo storage user = users[_epoch][msg.sender];
        user.claimed += reward;

        if (enableStaking) {
            LVL.safeIncreaseAllowance(address(levelStake), reward);
            levelStake.stake(_to, reward);
        } else {
            LVL.safeTransfer(_to, reward);
        }

        emit Claimed(_epoch, _to, reward, enableStaking);
    }

    function nextEpoch() external {
        require(msg.sender == distributor, "LevelReferralController::nextEpoch: !distributor");
        uint256 nextEpochTimestamp = getNextEpoch();
        require(block.timestamp >= nextEpochTimestamp, "LevelReferralController::nextEpoch: now < trigger time");

        oracle.update();

        epochs[currentEpoch].TWAP = oracle.lastTWAP();
        epochs[currentEpoch].allocationTime = block.timestamp;
        lastEpochTimestamp = nextEpochTimestamp;

        currentEpoch++;
        emit EpochStarted(currentEpoch);
    }

    // =============== RESTRICTED ===============

    function setDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "LevelReferralController::setDistributor: invalid address");
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    function setUpdater(address _updater) external onlyOwner {
        require(_updater != address(0), "LevelReferralController::setUpdater: invalid address");
        updater = _updater;
        emit UpdaterSet(updater);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(
            _oracle != address(0) && _oracle != address(oracle), "LevelReferralController::setOracle: invalid address"
        );
        oracle = ILVLOracle(_oracle);
        oracle.update();
        emit OracleSet(_oracle);
    }

    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        require(
            _epochDuration >= MIN_EPOCH_DURATION,
            "LevelReferralController::setEpochDuration: must >= MIN_EPOCH_DURATION"
        );
        epochDuration = _epochDuration;
        emit EpochDurationSet(epochDuration);
    }

    function setEnableStake(bool _enableStaking) external onlyOwner {
        if (enableStaking != _enableStaking) {
            enableStaking = _enableStaking;
        }
        emit EnableStakeSet(_enableStaking);
    }

    function withdrawLVL(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "LevelReferralController::withdrawLVL: invalid address");
        LVL.safeTransfer(_to, _amount);

        emit LVLWithdrawn(_to, _amount);
    }

    // ===============  EVENTS ===============
    event ReferrerSet(address indexed trader, address indexed referrer);
    event TradingPointUpdated(uint256 indexed epoch, address indexed trader, uint256 point);
    event ReferralPointUpdated(uint256 indexed epoch, address indexed referrer, address indexed trader, uint256 point);
    event Claimed(uint256 indexed epoch, address indexed to, uint256 reward, bool stake);
    event EpochStarted(uint256 indexed epoch);
    event EpochDurationSet(uint256 epochDuration);
    event UpdaterSet(address indexed updater);
    event OracleSet(address indexed updater);
    event DistributorSet(address indexed distributor);
    event EnableStakeSet(bool enable);
    event LVLWithdrawn(address indexed to, uint256 amount);
}
