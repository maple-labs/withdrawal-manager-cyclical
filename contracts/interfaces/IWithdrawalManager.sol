// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

/// @title Manages the withdrawal requests of a liquidity pool.
interface IWithdrawalManager {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @dev   Emitted when an account withdraws assets.
     *  @param account_ Address of the account.
     *  @param assets_  Amount of assets withdrawn by the account.
     */
    event AssetsWithdrawn(address indexed account_, uint256 assets_);

    /**
     *  @dev   Emitted when all shares belonging to a specific period are processed.
     *  @param period_ Index of the period whose shares have been processed.
     *  @param assets_ Amount of assets that have been made available for withdrawal.
     *  @param shares_ Amount of shares that could not be redeemed due to insufficient liquidity.
     */
    event PeriodProcessed(uint256 indexed period_, uint256 assets_, uint256 shares_);

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
     *  @dev   Emitted when the expected withdrawal period for an account changes.
     *  @param account_ Address of the account.
     *  @param period_  The period during which the account can perform a withdrawal.
     */
    event WithdrawalPending(address indexed account_, uint256 period_);

    /********************************/
    /*** State Changing Functions ***/
    /********************************/

    /**
     *  @dev    Transfers shares to the withdrawal manager.
     *          Locking additional shares will cause the withdrawal period to be updated.
     *          If any shares are locked and the withdrawal date is due, no additional shares can be locked until a withdrawal is performed.
     *  @param  sharesToLock_ Amount of shares to lock.
     *  @return totalShares_  Total amount of shares locked after the operation is performed.
     */
    function lockShares(uint256 sharesToLock_) external returns (uint256 totalShares_);

    /**
     *  @dev Redeems as many shares in the current withdrawal period as possible.
     *       Can only be called during a withdrawal period, and only once per withdrawal period.
     *       If not called explicitly it will be executed automatically before the first withdrawal of a period is performed.
     *       If no withdrawals are performed during a withdrawal period, and this function is not called, no shares will be redeemed.
     *       All shares in the same withdrawal period are processed at the same time, using the same exchange rate.
     */
    function processPeriod() external;

    /**
     *  @dev    Withdraws assets from the pool and optionally reclaims any leftover shares.
     *          Can only be called after shares have been locked, and only after the associated withdrawal period starts.
     *          Incase of insufficient liquidity only a portion of the assets will be withdrawn.
     *          The assets are split between all accounts proportional to their equity of all the shares in the period prior to their redemption.
     *          In case of insufficient liquidity any amount of leftover shares can be unlocked, the remaining shares will have their withdrawal period updated.
     *  @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     *  @return withdrawnAssets_ Amount of assets that were withdrawn.
     *  @return redeemedShares_  Amount of shares that were redeemed.
     *  @return remainingShares_ Amount of shares that remain locked.
     */
    function redeemPosition(uint256 sharesToReclaim_) external returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 remainingShares_);

    /**
     *  @dev    Transfers shares from the withdrawal manager to the sender.
     *          Unlocking shares will cause the pending withdrawal period to be updated.
     *          Unlocking all shares will cause the withdrawal to be cancelled.
     *          If any shares are locked and the withdrawal date is due, no shares can be unlocked until a withdrawal is performed.
     *  @param  sharesToReclaim_ Amount of shares the account wants to unlock.
     *  @return remainingShares_ Total amount of shares locked.
     */
    function unlockShares(uint256 sharesToReclaim_) external returns (uint256 remainingShares_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    function asset() external view returns (address asset_);

    function availableAssets(uint256 period_) external view returns (uint256 availableAssets_);

    function isProcessed(uint256 period_) external view returns (bool isProcesssed_);

    function leftoverShares(uint256 period_) external view returns (uint256 leftoverShares_);

    function lockedShares(address account_) external view returns (uint256 lockedShares_);

    function pendingWithdrawals(uint256 period_) external view returns (uint256 pendingWithdrawals_);

    function periodCooldown() external view returns (uint256 periodCooldown_);

    function periodDuration() external view returns (uint256 periodDuration_);

    function periodFrequency() external view returns (uint256 periodFrequency_);

    function periodStart() external view returns (uint256 periodStart_);

    function pool() external view returns (address pool_);

    function totalShares(uint256 period_) external view returns (uint256 totalShares_);

    function withdrawalPeriod(address account_) external view returns (uint256 withdrawalPeriod_);

}
