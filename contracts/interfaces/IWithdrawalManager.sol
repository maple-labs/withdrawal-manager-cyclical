// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IMapleProxied } from "../../modules/maple-proxy-factory/contracts/interfaces/IMapleProxied.sol";

import { IWithdrawalManagerStorage } from "./IWithdrawalManagerStorage.sol";

/// @title Manages the withdrawal requests of a liquidity pool.
interface IWithdrawalManager is IMapleProxied, IWithdrawalManagerStorage {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @dev   Emitted when the pool delegate reclaims assets that have not been withdrawn.
     *  @param cycleId_ Index of the cycle whose assets have been reclaimed.
     *  @param assets_  Amount of assets that have been reclaimed.
     */
    event AssetsReclaimed(uint256 indexed cycleId_, uint256 assets_);

    /**
     *  @dev   Emitted when an account withdraws assets.
     *  @param account_ Address of the account.
     *  @param assets_  Amount of assets withdrawn by the account.
     */
    event AssetsWithdrawn(address indexed account_, uint256 assets_);

    /**
     *  @dev   Emitted when all shares belonging to a specific cycle are processed.
     *  @param cycleId_ Index of the cycle whose shares have been processed.
     *  @param assets_  Amount of assets that have been made available for withdrawal.
     *  @param shares_  Amount of shares that could not be redeemed due to insufficient liquidity.
     */
    event CycleProcessed(uint256 indexed cycleId_, uint256 assets_, uint256 shares_);

    /**
     *  @dev   Emitted when an account locks their shares.
     *  @param account_ Address of the account.
     *  @param shares_  Amount of shares locked.
     */
    event SharesLocked(address indexed account_, uint256 shares_);

    /**
     *  @dev   Emitted when an account unlocks their shares.
     *  @param account_ Address of the account.
     *  @param shares_  Amount of shares unlocked.
     */
    event SharesUnlocked(address indexed account_, uint256 shares_);

    /**
     *  @dev   Emitted when a withdrawal is cancelled.
     *  @param account_ Address of the account.
     */
    event WithdrawalCancelled(address indexed account_);

    /**
     *  @dev   Emitted when the expected withdrawal cycle for an account changes.
     *  @param account_ Address of the account.
     *  @param cycleId_ The cycle during which the account can perform a withdrawal.
     */
    event WithdrawalPending(address indexed account_, uint256 cycleId_);

    /********************************/
    /*** State Changing Functions ***/
    /********************************/

    /**
     *  @dev    Transfers shares to the withdrawal manager.
     *          Locking additional shares will cause the withdrawal cycle to be updated.
     *          If any shares are locked and the withdrawal date is due, no additional shares can be locked until a withdrawal is performed.
     *  @param  sharesToLock_ Amount of shares to lock.
     *  @return totalShares_  Total amount of shares locked after the operation is performed.
     */
    function lockShares(uint256 sharesToLock_) external returns (uint256 totalShares_);

    /**
     *  @dev Redeems as many shares in the current withdrawal cycle as possible.
     *       Can only be called during a withdrawal cycle, and only once per withdrawal cycle.
     *       If not called explicitly it will be executed automatically before the first withdrawal of a cycle is performed.
     *       If no withdrawals are performed during a withdrawal cycle, and this function is not called, no shares will be redeemed.
     *       All shares in the same withdrawal cycle are processed at the same time, using the same exchange rate.
     */
    function processCycle() external;

    /**
     *  @dev    Reclaims all available assets from the specified withdrawal cycle.
     *          Can only be called by the pool delegate, and only when the specified withdrawal cycle has elapsed.
     *  @param  cycleId_         Withdrawal cycle from which available assets will be reclaimed.
     *  @return reclaimedAssets_ Amount of assets that were reclaimed.
     */
    function reclaimAssets(uint256 cycleId_) external returns (uint256 reclaimedAssets_);

    /**
     *  @dev    Withdraws assets from the pool and optionally reclaims any leftover shares.
     *          Can only be called after shares have been locked, and only after the associated withdrawal cycle starts.
     *          In case of insufficient liquidity only a portion of the assets will be withdrawn.
     *          The assets are split between all accounts proportional to their equity of all the shares in the cycle prior to their redemption.
     *          In case of insufficient liquidity any amount of leftover shares can be unlocked, the remaining shares will have their withdrawal cycle updated.
     *  @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     *  @return withdrawnAssets_ Amount of assets that were withdrawn.
     *  @return redeemedShares_  Amount of shares that were redeemed.
     *  @return remainingShares_ Amount of shares that remain locked.
     */
    function redeemPosition(uint256 sharesToReclaim_) external returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 remainingShares_);

    /**
     *  @dev   Adds a new configuration for withdrawal time intervals. If a "next" configuration is already in place, this will edit it.
     *  @param cycleDuration_            The full cycle duration for the configuration
     *  @param withdrawalWindowDuration_ Duration for the withdrawalWindow
     */
    function setNextConfiguration(uint256 cycleDuration_, uint256 withdrawalWindowDuration_) external;

    /**
     *  @dev    Transfers shares from the withdrawal manager to the sender.
     *          Unlocking shares will cause the pending withdrawal cycle to be updated.
     *          Unlocking all shares will cause the withdrawal to be cancelled.
     *          If any shares are locked and the withdrawal date is due, no shares can be unlocked until a withdrawal is performed.
     *  @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     *  @return remainingShares_ Total amount of shares locked.
     */
    function unlockShares(uint256 sharesToReclaim_) external returns (uint256 remainingShares_);

    /**********************/
    /*** View Functions ***/
    /**********************/

     /**
     *  @dev    Returns the total amount of available assets in a given cycle.
     *  @param  cycleId_         The index of the cycle to check.
     *  @return availableAssets_ The total number of available assets in `cycleId_`.
     */
    function availableAssets(uint256 cycleId_) external view returns (uint256 availableAssets_);

    /**
     *  @dev    Returns index for the cycle which `timestamp_` belongs to.
     *  @param  timestamp_  The unix timestamp to get the cycle from.
     *  @return cycleId_    The index of the cycle.
     */
    function getCycleId(uint256 timestamp_) external view returns (uint256 cycleId_);

    /**
     *  @dev    Returns timestamp boundaries of a given cycle.
     *  @param  cycleId_    The index of the cycle to check.
     *  @return cycleStart_ The timestamp of the cycle start.
     *  @return cycleEnd_   The timestamp of the cycle end.
     */
    function getCycleBounds(uint256 cycleId_) external view returns (uint256 cycleStart_, uint256 cycleEnd_);

    /**
     *  @dev    Returns timestamp of withdrawal window boundaries of a given cycle.
     *  @param  cycleId_ The index of the cycle to check.
     *  @return start_   The timestamp of the cycle start.
     *  @return end_     The timestamp of the cycle end.
     */
    function getWithdrawalWindowBounds(uint256 cycleId_) external view returns (uint256 start_, uint256 end_);

    /**
     *  @dev    Returns whether or not a given period has been processed.
     *  @param  cycleId_     The index of the cycle to check.
     *  @return isProcessed_ A boolean indicating if cycle has been processed.
     */
    function isProcessed(uint256 cycleId_) external view returns (bool isProcessed_);

    /**
     *  @dev    Returns the amount of leftover shares in a given cycle.
     *  @param  cycleId_        The index of the cycle to check.
     *  @return leftoverShares_ The total number of leftover shares in `cycleId_`.
     */
    function leftoverShares(uint256 cycleId_) external view returns (uint256 leftoverShares_);

    /**
     *  @dev    Returns the amount of locked shares fo an account.
     *  @param  account_      The address of the account to check.
     *  @return lockedShares_ The total number of locked shares.
     */
    function lockedShares(address account_) external view returns (uint256 lockedShares_);

    /**
     *  @dev    Returns the total amount of withdrawals requests in a given cycle.
     *  @param  cycleId_            The index of the cycle to check.
     *  @return pendingWithdrawals_ The total number of withdrawal requests in `cycleId_`.
     */
    function pendingWithdrawals(uint256 cycleId_) external view returns (uint256 pendingWithdrawals_);

    /**
     *  @dev    Returns the current duration of the cycle.
     *  @return cycleDuration_ The current amount of seconds of a cycle.
     */
    function cycleDuration() external view returns (uint256 cycleDuration_);

    /**
     *  @dev    Returns the total amount of shares to be withdrawn in a given cycle.
     *  @param  cycleId_     The index of the cycle to check.
     *  @return totalShares_ The total number of shares to be withdraw in `cycleId_`.
     */
    function totalShares(uint256 cycleId_) external view returns (uint256 totalShares_);

    /**
     *  @dev    The current cycle that `account_` is eligible to withdraw.
     *  @param  account_         The address of the account to check.
     *  @return withdrawalCycle_ The number/index of the cycle that account can withdraw.
     */
    function withdrawalCycleId(address account_) external view returns (uint256 withdrawalCycle_);

    /**
     *  @dev    The current duration, in seconds, of the withdrawal window.
     *  @return withdrawalWindowDuration_ Total amount of seconds in the withdrawalWindow.
     */
    function withdrawalWindowDuration() external view returns (uint256 withdrawalWindowDuration_);

}
