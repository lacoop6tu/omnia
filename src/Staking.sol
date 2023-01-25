// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";

// The new yield will be available after a locking period(28 days) or when a new yield is updated by admin, whichever comes first
// Solidity 0.8 compiler has built-in math operation overflows checks

contract Staking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Error__Amount_zero();
    error Error__Already_staked();
    error Error__Lock_too_long();
    error Error__Lock_too_short();
    error Error__Nothing_to_withdraw();
    error Error__Cannot_withdraw_yet();
    error Error__Not_enough_rewards_available();
    error Error__Nothing_to_claim();
    error Error__Not_staked();
    error Error__No_rewards_available();
    error Error__Arrays_mismatch();

    IERC20 public immutable token;

    uint256 public constant maxLock = 365 days;
    uint256 public constant minLock = 21 days;
    uint256 public constant epoch = 28 days;

    uint256 public availableRewards;

    event Deposit(address user, uint256 amount, uint256 lockedUntil);

    event Add(address user, uint256 amount);

    event Claim(address user, uint256 amount);

    event Withdraw(address user, uint256 amount);

    event Yield(address user, uint256 availableYield, uint256 lockedYield);

    mapping(address => Info) public deposits;

    struct Info {
        uint256 amount;
        uint256 lockedUntil;
        uint256 yieldAvailable;
        uint256 yieldLocked;
        uint256 lastYieldUpdate;
    }

    constructor(address _token) {
        token = IERC20(_token);
    }

    /// ======== External functions ======== ///

    /// @notice Stake an amount of OMNIA token for a fixed period of time
    /// @dev Sender has to approve this contract
    /// @param amount Amount to lock [wei]
    /// @param time Locking period [s]
    function stake(uint256 amount, uint256 time) external nonReentrant {
        if (amount == 0) revert Error__Amount_zero();
        if (deposits[msg.sender].amount != 0) revert Error__Already_staked();
        if (time > 365 days) revert Error__Lock_too_long();
        if (time < 21 days) revert Error__Lock_too_short();

        deposits[msg.sender].amount = amount;
        deposits[msg.sender].lockedUntil = block.timestamp + time;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, block.timestamp + time);
    }

    /// @notice Add an amount of OMNIA for the same fixed period, yield will be updated by admin in the next epoch
    /// @dev Sender has to approve this contract
    /// @param amount Amount to add to the stake [wei]
    function addToStake(uint256 amount) external nonReentrant {
        if (deposits[msg.sender].amount == 0) revert Error__Not_staked();
        if (amount == 0) revert Error__Amount_zero();

        deposits[msg.sender].amount += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Add(msg.sender, amount); // used off-chain for the next yield epoch
    }

    /// @notice Claim all Available yield, there must be enough rewards added by the admin for distributing the yield
    function claim_yield() external nonReentrant {
        uint256 amount = _claim();

        token.safeTransfer(msg.sender, amount);

        emit Claim(msg.sender, amount);
    }

    /// @notice Withdraw all amount staked if lock expired
    function withdraw() external nonReentrant {
        uint256 amount = _withdraw();

        token.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Withdraw all amount staked if lock expired and also claims all available yield (if enough rewards)
    function withdraw_and_claim() external nonReentrant {
        uint256 withdrawAmount = _withdraw();
        uint256 yieldAmount = _claim();

        token.safeTransfer(msg.sender, yieldAmount + withdrawAmount);

        emit Withdraw(msg.sender, withdrawAmount);
        emit Claim(msg.sender, yieldAmount);
    }

    /// ======== Internal functions ======== ///

    function _withdraw() internal returns (uint256 amount) {
        if (deposits[msg.sender].amount == 0) revert Error__Nothing_to_withdraw();
        if (deposits[msg.sender].lockedUntil > block.timestamp) revert Error__Cannot_withdraw_yet();

        amount = deposits[msg.sender].amount;
        deposits[msg.sender].amount = 0;
        deposits[msg.sender].lockedUntil = 0;
    }

    function _claim() internal returns (uint256 amount) {
        amount = deposits[msg.sender].yieldAvailable;

        // Check if there's some unlocked yield and add it
        if (block.timestamp >= deposits[msg.sender].lastYieldUpdate + epoch) {
            amount += deposits[msg.sender].yieldLocked;
            deposits[msg.sender].yieldLocked = 0;
        }

        if (amount == 0) revert Error__Nothing_to_claim();
        if (availableRewards == 0) revert Error__No_rewards_available();

        // Will throw if not enough rewards are available, so we avoid using other users' balances (last chair dance)
        if (availableRewards < amount) revert Error__Not_enough_rewards_available();

        deposits[msg.sender].yieldAvailable = 0;
        availableRewards -= amount;
    }

    /// ======== View functions ======== ///

    function getUserInfo(address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        Info memory info = deposits[user];
        return (
            info.amount,
            info.lockedUntil,
            info.yieldAvailable,
            info.yieldLocked,
            info.lastYieldUpdate
        );
    }

    /// ======== Admin functions ======== ///

    /// @notice Add locked rewards for users, unlock the previous ones if any
    /// @dev Only contract owner can call
    /// @param users Users to reward
    /// @param yields Correspoding yields
    function updateYields(address[] calldata users, uint256[] calldata yields)
        external
        onlyOwner
    {
        if (users.length != yields.length) revert Error__Arrays_mismatch();

      
        for (uint256 i = 0; i < users.length; ) {
            deposits[users[i]].yieldAvailable += deposits[users[i]].yieldLocked;
            deposits[users[i]].yieldLocked = yields[i];
            deposits[users[i]].lastYieldUpdate = block.timestamp;
            emit Yield(users[i], deposits[users[i]].yieldAvailable, yields[i]);

            // In this case we don't need the overflow check and we can save some gas
            unchecked {
                i++;
            }
        }
    }

    /// @notice Add OMNIA rewards for users
    /// @dev Only contract owner can call
    /// @param amount Rewards(yields) to be distributed
    function addRewards(uint256 amount) external onlyOwner {
        availableRewards += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw any OMNIA rewards in case of a shutdown (not users stakes)
    /// @dev Only contract owner can call
    function withdrawRewards() external onlyOwner {
        if (availableRewards > 0) {
            uint256 amount = availableRewards;
            availableRewards = 0;
            token.safeTransfer(msg.sender, amount);
        }
    }
}
