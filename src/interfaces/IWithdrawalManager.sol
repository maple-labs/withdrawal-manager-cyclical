// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IERC20 } from "../../lib/erc20/src/interfaces/IERC20.sol";

/// @title Manages the withdrawal mechanism of a liquidity pool.
interface IWithdrawalManager {

    /**************/
    /*** Events ***/
    /**************/

    /**
     * @dev   Emitted when an account locks their shares.
     * @param account Address of the account.
     * @param shares  Amount of shares locked.
     */
    event SharesLocked(address indexed account, uint256 shares);

    /**
     * @dev   Emitted when an account unlocks their shares.
     * @param account Address of the account.
     * @param shares  Amount of shares unlocked.
     */
    event SharesUnlocked(address indexed account, uint256 shares);

    /**
     * @dev   Emitted when the expected withdrawal period for an account changes.
     * @param account Address of the account.
     * @param period  The period during which the account can perform a withdrawal.
     */
    event WithdrawalPending(address indexed account, uint256 period);

    /**
     * @dev   Emitted when a withdrawal is cancelled.
     * @param account Address of the account.
     */
    event WithdrawalCancelled(address indexed account);

    /**
     * @dev   Emitted when an account withdraws funds.
     * @param account Address of the account.
     * @param funds   Amount of funds withdrawn by the account.
     */
    event FundsWithdrawn(address indexed account, uint256 funds);

    /**
     * @dev   Emitted when all shares belonging to a specific period are processed.
     * @param period Index of the period whose shares have been processed.
     * @param funds  Amount of funds that have been made available for withdrawal.
     * @param shares Amount of shares that could not be redeemed due to insufficient liquidity.
     */
    event PeriodProcessed(uint256 indexed period, uint256 funds, uint256 shares);

    /********************************/
    /*** State Changing Functions ***/
    /********************************/

    /**
     * @dev    Transfers shares to the withdrawal manager.
     *         Locking additional shares will cause the withdrawal period to be updated.
     *         If any shares are locked and the withdrawal date is due, no additional shares can be locked until a withdrawal is performed.
     * @param  sharesToLock_ Amount of shares to lock.
     * @return totalShares_  Total amount of shares locked after the operation is performed.
     */
    function lockShares(uint256 sharesToLock_) external returns (uint256 totalShares_);

    /**
     * @dev Redeems as many shares in the current withdrawal period as possible.
     *      Can only be called during a withdrawal period, and only once per withdrawal period.
     *      If not called explicitly it will be executed automatically before the first withdrawal of a period is performed.
     *      If no withdrawals are performed during a withdrawal period, and this function is not called, no shares will be redeemed.
     *      All shares in the same withdrawal period are processed at the same time, using the same exchange rate.
     */
    function processPeriod() external;

    // TODO: Add function for allowing pool delegate to reclaim non-withdrawn funds: function reclaimFunds() external;

    /**
     * @dev    Withdraws funds from the pool and optionally reclaims any leftover shares.
     *         Can only be called after shares have been locked, and only after the associated withdrawal period starts.
     *         Incase of insufficient liquidity only a portion of the funds will be withdrawn.
     *         The funds are split between all accounts proportional to their equity of all the shares in the period prior to their redemption.
     *         In case of insufficient liquidity any amount of leftover shares can be unlocked, the remaining shares will have their withdrawal period updated.
     * @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     * @return withdrawnFunds_  Amount of funds that were withdrawn.
     * @return redeemedShares_  Amount of shares that were redeemed.
     * @return remainingShares_ Amount of shares that remain locked.
     */
    function redeemPosition(uint256 sharesToReclaim_) external returns (uint256 withdrawnFunds_, uint256 redeemedShares_, uint256 remainingShares_);

    /**
     * @dev    Transfers shares from the withdrawal manager to the sender.
     *         Unlocking shares will cause the pending withdrawal period to be updated.
     *         Unlocking all shares will cause the withdrawal to be cancelled.
     *         If any shares are locked and the withdrawal date is due, no shares can be unlocked until a withdrawal is performed.
     * @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     * @return remainingShares_ Total amount of shares locked.
     */
    function unlockShares(uint256 sharesToReclaim_) external returns (uint256 remainingShares_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    function fundsAsset() external view returns (address);

    function periodCooldown() external view returns (uint256);

    function periodDuration() external view returns (uint256);

    function periodFrequency() external view returns (uint256);

    function periodStart() external view returns (uint256);

    function pool() external view returns (address);

    function lockedShares(address account_) external view returns (uint256);

    function withdrawalPeriod(address account_) external view returns (uint256);

    function totalShares(uint256 period_) external view returns (uint256);

    function pendingWithdrawals(uint256 period_) external view returns (uint256);

    function availableFunds(uint256 period_) external view returns (uint256);

    function leftoverShares(uint256 period_) external view returns (uint256);

    function isProcessed(uint256 period_) external view returns (bool);

}
