// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ILGOStakingView} from "../interfaces/ILGOStakingView.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {ILGOToken} from "../interfaces/ILGOToken.sol";

contract GovernanceRedemptionPoolV2 is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct Snapshot {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lgoSupply;
        uint256 llpBalance;
    }

    struct SnapshotV2 {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lgoSupply;
        uint256 llpBalance;
        uint256 lvlUsdtLPBalance;
    }

    uint256 public constant MIN_REDEEM_DURATION = 1 days;
    uint8 public constant VERSION = 2;

    ILGOToken public LGO;
    IERC20 public LLP;

    ITreasury public treasury;
    ILGOStakingView public lgoView;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // begin: deprecated vars
    Snapshot public snapshot;
    // end: deprecated vars

    uint256 public redeemDuration;

    // ===== begin: V2 Storage ====
    IERC20 public lvlUsdtLP;
    SnapshotV2 public snapshotV2;
    // ===== end: V2 Storage ====

    function initialize(address _llp, address _lgo, address _lgoView, address _treasury) external initializer {
        require(_llp != address(0), "GovernanceRedemptionPool::initialize: invalid address");
        require(_lgo != address(0), "GovernanceRedemptionPool::initialize: invalid address");
        require(_lgoView != address(0), "GovernanceRedemptionPool::initialize: invalid address");
        require(_treasury != address(0), "GovernanceRedemptionPool::initialize: invalid address");
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        LLP = IERC20(_llp);
        LGO = ILGOToken(_lgo);
        lgoView = ILGOStakingView(_lgoView);
        treasury = ITreasury(_treasury);
        redeemDuration = 2 days;
    }

    function reinit_v2(address _lvlUsdtLP) external reinitializer(VERSION) {
        require(
            _lvlUsdtLP != address(0) && _lvlUsdtLP != address(LLP),
            "GovernanceRedemptionPool::reinit_v2: invalid address"
        );
        lvlUsdtLP = IERC20(_lvlUsdtLP);
        snapshotV2 = SnapshotV2({
            startTimestamp: snapshot.startTimestamp,
            endTimestamp: snapshot.endTimestamp,
            lgoSupply: snapshot.lgoSupply,
            llpBalance: snapshot.llpBalance,
            lvlUsdtLPBalance: 0
        });
    }

    modifier onlyRedemptionActive() {
        require(isRedemptionActive(), "GovernanceRedemptionPool::onlyRedemptionActive: redemption is not active");
        _;
    }

    // =============== USER FUNCTIONS ===============

    function startNextBatch() external onlyRole(CONTROLLER_ROLE) {
        require(address(LLP) != address(0), "GovernanceRedemptionPool::startNextBatch: no llp token");
        require(address(treasury) != address(0), "GovernanceRedemptionPool::startNextBatch: no treasury set");
        require(!isRedemptionActive(), "GovernanceRedemptionPool::startNextBatch: previous batch is not completed");
        snapshotV2 = getNextSnapshot();

        emit NextBatchStarted(block.timestamp, snapshotV2.startTimestamp, snapshotV2.endTimestamp, snapshotV2.lgoSupply);
    }

    function redeem(address _to, uint256 _amount) external onlyRedemptionActive nonReentrant {
        require(_to != address(0), "GovernanceRedemptionPool::redeem: invalid address");
        (uint256 llpAmount, uint256 lvlUsdtLPAmount) = redeemable(_amount);
        require(llpAmount != 0 || lvlUsdtLPAmount != 0, "GovernanceRedemptionPool::redeem: !redeemable");
        LGO.burnFrom(msg.sender, _amount);
        treasury.distribute(address(LLP), _to, llpAmount);
        treasury.distribute(address(lvlUsdtLP), _to, lvlUsdtLPAmount);

        emit Redeemed(msg.sender, _to, _amount, address(LLP), llpAmount, lvlUsdtLPAmount);
    }

    function redeemToToken(address _to, uint256 _amount, address _tokenOut, uint256 _minimumAmountOut)
        external
        onlyRedemptionActive
        nonReentrant
    {
        require(_to != address(0), "GovernanceRedemptionPool::redeemToToken: invalid address");
        (uint256 llpAmount, uint256 lvlUsdtLPAmount) = redeemable(_amount);

        require(llpAmount != 0 || lvlUsdtLPAmount != 0, "GovernanceRedemptionPool::redeemToToken: !redeemable");
        LGO.burnFrom(msg.sender, _amount);
        treasury.distribute(address(lvlUsdtLP), _to, lvlUsdtLPAmount);
        treasury.convertLLPToToken(_to, _tokenOut, llpAmount, _minimumAmountOut);

        emit Redeemed(msg.sender, _to, _amount, address(LLP), llpAmount, lvlUsdtLPAmount);
    }

    // =============== VIEW FUNCTIONS ===============

    function redeemable(uint256 _lgoAmount) public view returns (uint256 llpAmount, uint256 lvlUsdtLPAmount) {
        if (isRedemptionActive() && snapshotV2.lgoSupply > 0 && _lgoAmount <= snapshotV2.lgoSupply) {
            llpAmount = _lgoAmount * snapshotV2.llpBalance / snapshotV2.lgoSupply;
            lvlUsdtLPAmount = _lgoAmount * snapshotV2.lvlUsdtLPBalance / snapshotV2.lgoSupply;
        }
    }

    function getNextSnapshot() public view returns (SnapshotV2 memory _snapshot) {
        _snapshot = SnapshotV2({
            startTimestamp: block.timestamp,
            endTimestamp: block.timestamp + redeemDuration,
            lgoSupply: lgoView.estimatedLGOCirculatingSupply(),
            llpBalance: LLP.balanceOf(address(treasury)),
            lvlUsdtLPBalance: lvlUsdtLP.balanceOf(address(treasury))
        });
    }

    function isRedemptionActive() public view returns (bool) {
        return block.timestamp >= snapshotV2.startTimestamp && block.timestamp < snapshotV2.endTimestamp;
    }

    // =============== RESTRICTED ===============

    function setLgoStakingView(address _lgoView) external onlyRole(ADMIN_ROLE) {
        require(_lgoView != address(0), "GovernanceRedemptionPool::setLgoStakingView: invalid address");
        lgoView = ILGOStakingView(_lgoView);
        emit LGOStakingViewSet(_lgoView);
    }

    function setRedeemDuration(uint256 _duration) external onlyRole(ADMIN_ROLE) {
        require(_duration >= MIN_REDEEM_DURATION, "GovernanceRedemptionPool::setRedeemDuration: < MIN_REDEEM_DURATION");
        redeemDuration = _duration;
        emit RedeemDurationSet(_duration);
    }

    function stopRedemption() external onlyRedemptionActive onlyRole(CONTROLLER_ROLE) {
        snapshotV2.endTimestamp = block.timestamp;
        emit RedemptionStopped();
    }

    /* ========== EVENTS ========== */

    event RedemptionStopped();
    event RedeemDurationSet(uint256 _duration);
    event LGOStakingViewSet(address indexed _addr);
    event NextBatchStarted(uint256 _time, uint256 _start, uint256 _end, uint256 _lgoSupply);
    event Redeemed(
        address indexed _from,
        address indexed _to,
        uint256 _amount,
        address _tokenOut,
        uint256 _amountOut,
        uint256 lvlUsdtLPAmountOut
    );
}
