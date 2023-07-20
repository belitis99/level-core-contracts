// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ILlpRewardDistributor} from "../interfaces/ILlpRewardDistributor.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LgoStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    /*========================== VARIABLES ============================ */

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    uint256 private constant ACC_REWARD_PRECISION = 1e12;

    IERC20 public lgo;
    ILlpRewardDistributor public llpRewardDistributor;
    uint256 public lastUpdateRewardTime;
    uint256 public accRewardPerShare;
    mapping(address => UserInfo) public userInfo;

    function initialize(address _lgo, address _llpRewardDistributor) external initializer {
        require(_lgo != address(0), "LgoStaking:initialize: invalid LGO");
        require(_llpRewardDistributor != address(0), "LgoStaking:initialize: invalid reward distributor");
        __Ownable_init();
        __ReentrancyGuard_init();
        lgo = IERC20(_lgo);
        llpRewardDistributor = ILlpRewardDistributor(_llpRewardDistributor);
    }

    /*==================================== VIEWS ==================================*/
    function getRewardToken() external view returns (address) {
        return llpRewardDistributor.rewardToken();
    }

    function pendingRewards(address _to) external view returns (uint256) {
        UserInfo memory user = userInfo[_to];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 _totalStakedAmount = lgo.balanceOf(address(this));
        if (block.timestamp > lastUpdateRewardTime && _totalStakedAmount != 0) {
            uint256 reward = (block.timestamp - lastUpdateRewardTime) * llpRewardDistributor.rewardsPerSecond();
            _accRewardPerShare += (reward * ACC_REWARD_PRECISION) / _totalStakedAmount;
        }
        return uint256(int256((user.amount * _accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt);
    }

    function getRewardsPerSecond() external view returns (uint256) {
        return llpRewardDistributor.rewardsPerSecond();
    }

    function withdrawableTokens(address _token) external view returns (bool) {
        return llpRewardDistributor.withdrawableTokens(_token);
    }

    /*==================================== MUTATIVE ===================================*/

    function stake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "LgoStaking::stake: amount > 0");
        address sender = msg.sender;
        updateRewards();
        UserInfo memory _userInfo = userInfo[_to];
        _userInfo.amount += _amount;
        _userInfo.rewardDebt += int256((_amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        userInfo[_to] = _userInfo;
        lgo.safeTransferFrom(sender, address(this), _amount);
        emit Staked(sender, _to, _amount);
    }

    function unstake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "LgoStaking::unstake: amount > 0");
        address sender = msg.sender;
        UserInfo memory _userInfo = userInfo[sender];
        require(_userInfo.amount >= _amount, "LgoStaking::unstake: unstake amount > staked amount");
        updateRewards();
        _userInfo.amount -= _amount;
        _userInfo.rewardDebt -= int256((_amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        userInfo[sender] = _userInfo;
        lgo.safeTransfer(_to, _amount);
        emit Unstaked(sender, _to, _amount);
    }

    function claimRewards(address _to) external nonReentrant {
        updateRewards();
        address sender = msg.sender;
        UserInfo memory user = userInfo[sender];
        int256 _accumulatedReward = int256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingRewards = uint256(_accumulatedReward - user.rewardDebt);
        user.rewardDebt = _accumulatedReward;
        userInfo[sender] = user;
        if (_pendingRewards != 0) {
            llpRewardDistributor.transferRewards(_to, _pendingRewards);
            emit Claimed(sender, _to, _pendingRewards);
        }
    }

    function claimRewardsToSingleToken(address _to, address _rewardTokenOut, uint256 _minAmountOut)
        external
        nonReentrant
    {
        require(_rewardTokenOut != address(0), "LgoStaking::claimRewards: Invalid address!");
        updateRewards();
        address sender = msg.sender;
        UserInfo memory user = userInfo[sender];
        int256 _accumulatedReward = int256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingRewards = uint256(_accumulatedReward - user.rewardDebt);
        user.rewardDebt = _accumulatedReward;
        userInfo[sender] = user;
        if (_pendingRewards != 0) {
            llpRewardDistributor.transferRewardsToSingleToken(_to, _pendingRewards, _rewardTokenOut, _minAmountOut);
            emit Claimed(msg.sender, _to, _pendingRewards);
        }
    }

    function updateRewards() public {
        uint256 _totalStakedAmount = lgo.balanceOf(address(this));
        if (block.timestamp > lastUpdateRewardTime) {
            uint256 reward = (block.timestamp - lastUpdateRewardTime) * llpRewardDistributor.rewardsPerSecond();
            accRewardPerShare =
                accRewardPerShare + (_totalStakedAmount == 0 ? 0 : (reward * ACC_REWARD_PRECISION) / _totalStakedAmount);
        }
        lastUpdateRewardTime = block.timestamp;
    }
    /*==================================== RESTRICTED ===================================*/

    function setLlpRewardDistributor(address _llpRewardDistributor) external onlyOwner {
        require(_llpRewardDistributor != address(0), "LgoStaking::setLlpRewardDistributor: Invalid address");
        llpRewardDistributor = ILlpRewardDistributor(_llpRewardDistributor);
        emit LlpRewardDistributorSet(_llpRewardDistributor);
    }

    /*==================================== EVENTS =================================*/

    event Staked(address indexed _from, address indexed _to, uint256 _amount);
    event Unstaked(address indexed _from, address indexed _to, uint256 _amount);
    event Claimed(address indexed _from, address indexed _to, uint256 _amount);
    event LlpRewardDistributorSet(address indexed _llpRewardDistributor);
}
