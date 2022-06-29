// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20Helper }        from "../modules/erc20-helper/src/ERC20Helper.sol";
import { IMapleProxyFactory } from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike, IPoolManagerLike } from "./interfaces/Interfaces.sol";
import { IWithdrawalManager }          from "./interfaces/IWithdrawalManager.sol";

// TODO: Reduce error message lengths / use custom errors.
// TODO: Optimize storage use, investigate struct assignment.
// TODO: Check gas usage and contract size.

/// @title Manages the withdrawal requests of a liquidity pool.
contract WithdrawalManager is IWithdrawalManager, MapleProxiedInternals {

    struct WithdrawalRequest {
        uint256 lockedShares;      // Amount of shares that have been locked by an account.
        uint256 withdrawalPeriod;  // Index of the pending withdrawal period.
    }

    struct WithdrawalPeriodState {
        uint256 totalShares;         // Total amount of shares that have been locked into this withdrawal period.
                                     // This value does not change after shares are redeemed for assets.
        uint256 pendingWithdrawals;  // Number of accounts that have yet to withdraw from this withdrawal period. Used to collect dust on the last withdrawal.
        uint256 availableAssets;     // Current amount of assets available for withdrawal. Decreases after an account performs a withdrawal.
        uint256 leftoverShares;      // Current amount of shares available for unlocking. Decreases after an account unlocks them.
        bool    isProcessed;         // Defines if the shares belonging to this withdrawal period have been processed.
    }

    // Contract dependencies.
    address public override asset;        // Underlying liquidity asset.
    address public override pool;         // Instance of a v2 pool.
    address public override poolManager;  // Pool's manager contract.

    // TODO: Allow updates of period / cooldown.
    uint256 public override periodStart;      // Beginning of the first withdrawal period.
    uint256 public override periodDuration;   // Duration of each withdrawal period.
    uint256 public override periodFrequency;  // How frequently a withdrawal period occurs.
    uint256 public override periodCooldown;   // Amount of time before shares become eligible for withdrawal. TODO: Remove in a separate PR.

    mapping(address => WithdrawalRequest) public requests;

    // The mapping key is the index of the withdrawal period (starting from 0).
    // TODO: Replace period keys with timestamp keys.
    mapping(uint256 => WithdrawalPeriodState) public periodStates;

    /***********************/
    /*** Proxy Functions ***/
    /***********************/

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "WM:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "WM:M:FAILED");
    }

    function setImplementation(address newImplementation_) external override {
        require(msg.sender == _factory(),               "WM:SI:NOT_FACTORY");
        require(_setImplementation(newImplementation_), "WM:SI:FAILED");
    }

    function upgrade(uint256 toVersion_, bytes calldata arguments_) external override {
        require(msg.sender == IPoolLike(pool).poolDelegate(), "WM:U:NOT_PD");

        emit Upgraded(toVersion_, arguments_);

        IMapleProxyFactory(_factory()).upgradeInstance(toVersion_, arguments_);
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    // TODO: Add permissioning and only allow the pool to call external functions. Add `account_` parameter and perform operations on behalf of the account.
    // TODO: Consider renaming lockShares/unlockShares to depositShares/withdrawShares.

    function lockShares(uint256 sharesToLock_) external override returns (uint256 totalShares_) {
        // Transfer the requested amount of shares from the account.
        totalShares_ = _lockShares(msg.sender, sharesToLock_);

        // Get the current and next available withdrawal period.
        ( uint256 currentPeriod, uint256 nextPeriod ) = _getWithdrawalPeriods(msg.sender);

        // Update the request and all affected period states.
        _updateRequest(msg.sender, totalShares_, nextPeriod);
        _updatePeriodState(totalShares_ - sharesToLock_, totalShares_, currentPeriod, nextPeriod);
    }

    // TODO: Check if ACL should be used here.
    function processPeriod() external override {
        // Check if the current period has already been processed.
        uint256 period = _getPeriod(block.timestamp);
        require(!periodStates[period].isProcessed, "WM:PP:DOUBLE_PROCESS");

        ( , uint256 periodEnd ) = _getWithdrawalPeriodBounds(period);
        _processPeriod(period, periodEnd);
    }

    function reclaimAssets(uint256 period_) external override returns (uint256 reclaimedAssets_) {
        // Reclaiming can only be performed by the pool delegate.
        require(msg.sender == IPoolLike(pool).poolDelegate(), "WM:RA:NOT_PD");

        // Assets can be reclaimed only after the withdrawal period has elapsed.
        ( , uint256 periodEnd ) = _getWithdrawalPeriodBounds(period_);
        require(block.timestamp >= periodEnd, "WM:RA:EARLY_RECLAIM");

        WithdrawalPeriodState storage periodState = periodStates[period_];

        // Check if there are any assets that have not been withdrawn yet.
        reclaimedAssets_ = periodState.availableAssets;
        require(reclaimedAssets_ != 0, "WM:RA:ZERO_ASSETS");

        // Deposit all available assets back into the pool.
        require(ERC20Helper.approve(address(asset), address(pool), reclaimedAssets_), "WM:RA:APPROVE_FAIL");

        // TODO: Is using the deposit function the best approach? Check how deposit is implemented in PoolV2 later and what could go wrong here.
        uint256 mintedShares = IPoolLike(pool).deposit(reclaimedAssets_, address(this));

        // Increase the number of leftover shares by the amount that was minted.
        periodState.leftoverShares += mintedShares;  // TODO: Check if this causes conflicts with existing leftover shares.
        periodState.availableAssets = 0;

        emit AssetsReclaimed(period_, reclaimedAssets_);
    }

    function redeemPosition(uint256 sharesToReclaim_) external override returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 reclaimedShares_) {
        // Check if a withdrawal request was made.
        uint256 personalShares = requests[msg.sender].lockedShares;
        require(personalShares != 0, "WM:RP:NO_REQUEST");

        // Get the current and next available withdrawal period.
        ( uint256 currentPeriod, uint256 nextPeriod ) = _getWithdrawalPeriods(msg.sender);

        // Get the start and end of the current withdrawal period.
        ( uint256 periodStart_, uint256 periodEnd ) = _getWithdrawalPeriodBounds(currentPeriod);

        require(block.timestamp >= periodStart_, "WM:RP:EARLY_WITHDRAW");

        // If the period has not been processed yet, do so before the withdrawal.
        if (!periodStates[currentPeriod].isProcessed) {
            _processPeriod(currentPeriod, periodEnd);
        }

        ( withdrawnAssets_, redeemedShares_, reclaimedShares_ ) = _withdrawAndUnlock(msg.sender, sharesToReclaim_, personalShares, currentPeriod);

        // Update the request and the state of all affected withdrawal periods.
        uint256 remainingShares = personalShares - redeemedShares_ - reclaimedShares_;
        _updateRequest(msg.sender, remainingShares, nextPeriod);
        _updatePeriodState(personalShares, remainingShares, currentPeriod, nextPeriod);
    }

    function unlockShares(uint256 sharesToReclaim_) external override returns (uint256 remainingShares_) {
        // Transfer the requested amount of shares to the account.
        remainingShares_ = _unlockShares(msg.sender, sharesToReclaim_);

        // Get the current and next available withdrawal period.
        ( uint256 currentPeriod, uint256 nextPeriod ) = _getWithdrawalPeriods(msg.sender);

        // Update the request and all affected period states.
        _updateRequest(msg.sender, remainingShares_, nextPeriod);
        _updatePeriodState(remainingShares_ + sharesToReclaim_, remainingShares_, currentPeriod, nextPeriod);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _lockShares(address account_, uint256 sharesToLock_) internal returns (uint256 totalShares_) {
        require(sharesToLock_ != 0, "WM:LS:ZERO_AMOUNT");

        // If a withdrawal is due no shares can be locked.
        uint256 previousShares = requests[account_].lockedShares;
        require(previousShares == 0 || _isWithinCooldown(account_), "WM:LS:WITHDRAW_DUE");

        // Transfer the shares into the withdrawal manager.
        require(ERC20Helper.transferFrom(pool, account_, address(this), sharesToLock_), "WM:LS:TRANSFER_FAIL");

        // Calculate the total amount of shares.
        totalShares_ = previousShares + sharesToLock_;

        emit SharesLocked(account_, sharesToLock_);
    }

    function _movePeriodShares(uint256 period_, uint256 nextPeriod_, uint256 currentShares_, uint256 nextShares_) internal {
        // If the account already has locked shares, remove them from the current period.
        if (currentShares_ != 0) {
            periodStates[period_].totalShares        -= currentShares_;
            periodStates[period_].pendingWithdrawals -= 1;
        }

        // Add shares into the next period if necessary.
        if (nextShares_ != 0) {
            periodStates[nextPeriod_].totalShares        += nextShares_;
            periodStates[nextPeriod_].pendingWithdrawals += 1;
        }
    }

    function _processPeriod(uint256 period_, uint256 periodEnd) internal {
        WithdrawalPeriodState storage periodState = periodStates[period_];

        // If the withdrawal period elapsed, perform no redemption of shares.
        if (block.timestamp >= periodEnd) {
            periodState.leftoverShares = periodState.totalShares;
            periodState.isProcessed = true;
            return;
        }

        uint256 totalShares_     = IPoolLike(pool).maxRedeem(address(this));
        uint256 periodShares     = periodState.totalShares;
        uint256 redeemableShares = totalShares_ > periodShares ? periodShares : totalShares_;

        // Calculate amount of available assets and leftover shares.
        uint256 availableAssets_ = redeemableShares > 0 ? IPoolManagerLike(poolManager).redeem(redeemableShares, address(this), address(this)) : 0;
        uint256 leftoverShares_  = periodShares - redeemableShares;

        // Update the withdrawal period state.
        periodState.availableAssets = availableAssets_;
        periodState.leftoverShares  = leftoverShares_;
        periodState.isProcessed     = true;

        emit PeriodProcessed(period_, availableAssets_, leftoverShares_);
    }

    function _unlockShares(address account_, uint256 sharesToReclaim_) internal returns (uint256 remainingShares_) {
        require(sharesToReclaim_ != 0, "WM:US:ZERO_AMOUNT");

        // If a withdrawal is due no shares can be unlocked.
        require(_isWithinCooldown(account_), "WM:US:WITHDRAW_DUE");

        // Transfer shares from the withdrawal manager to the account.
        require(ERC20Helper.transfer(pool, account_, sharesToReclaim_), "WM:US:TRANSFER_FAIL");

        // Calculate the amount of remaining shares.
        remainingShares_ = requests[account_].lockedShares - sharesToReclaim_;

        emit SharesUnlocked(account_, sharesToReclaim_);
    }

    // TODO: Investigate using int256 for updating the period state more easily.
    function _updatePeriodShares(uint256 period_, uint256 currentShares_, uint256 nextShares_) internal {
        // If additional shares were locked, increase the amount of total shares locked in the period.
        if (nextShares_ > currentShares_) {
            periodStates[period_].totalShares += nextShares_ - currentShares_;
        }
        // If shares were unlocked, decrease the amount of total shares locked in the period.
        else {
            periodStates[period_].totalShares -= currentShares_ - nextShares_;
        }

        // If the account has no remaining shares, decrease the number of withdrawal requests.
        if (nextShares_ == 0) {
            periodStates[period_].pendingWithdrawals -= 1;
        }
    }

    function _updatePeriodState(uint256 currentShares_, uint256 nextShares_, uint256 currentPeriod_, uint256 nextPeriod_) internal {
        // If shares do not need to be moved across withdrawal periods, just update the amount of shares.
        if (currentPeriod_ == nextPeriod_) {
            _updatePeriodShares(nextPeriod_, currentShares_, nextShares_);
        }
        // If the next period is different, move all the shares from the current period to the new one.
        else {
            _movePeriodShares(currentPeriod_, nextPeriod_, currentShares_, nextShares_);
        }
    }

    function _updateRequest(address account_, uint256 shares_, uint256 period_) internal {
        // If any shares are remaining, perform the update.
        if (shares_ != 0) {
            requests[account_] = WithdrawalRequest({ lockedShares: shares_, withdrawalPeriod: period_ });
            emit WithdrawalPending(account_, period_);
        }
        // Otherwise, clean up the request.
        else {
            delete requests[account_];
            emit WithdrawalCancelled(account_);
        }
    }

    function _withdrawAndUnlock(
        address account_,
        uint256 sharesToReclaim_,
        uint256 personalShares_,
        uint256 period_
    )
        internal returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 reclaimedShares_)
    {
        // Cache variables.
        WithdrawalPeriodState storage periodState = periodStates[period_];
        uint256 activeShares     = periodState.totalShares;
        uint256 availableAssets_ = periodState.availableAssets;
        uint256 leftoverShares_  = periodState.leftoverShares;
        uint256 accountCount     = periodState.pendingWithdrawals;

        // [personalShares / activeShares] is the percentage of the assets / shares in the withdrawal period that the account is entitled to claim.
        // Multiplying this amount by the amount of leftover shares and available assets calculates his "fair share".
        withdrawnAssets_          = accountCount > 1 ? availableAssets_ * personalShares_ / activeShares : availableAssets_;
        uint256 reclaimableShares = accountCount > 1 ? leftoverShares_ * personalShares_ / activeShares : leftoverShares_;

        // Remove the entitled assets and shares from the withdrawal period.
        periodState.availableAssets -= withdrawnAssets_;
        periodState.leftoverShares  -= reclaimableShares;

        // Calculate how many shares have been redeemed, and how many shares will be reclaimed.
        redeemedShares_  = personalShares_ - reclaimableShares;
        reclaimedShares_ = sharesToReclaim_ < reclaimableShares ? sharesToReclaim_ : reclaimableShares;  // TODO: Revert if `sharesToReclaim_` is too large?

        // Transfer the assets to the account.
        if (withdrawnAssets_ != 0) {
            require(ERC20Helper.transfer(asset, account_, withdrawnAssets_), "WM:WAU:TRANSFER_FAIL");
            emit AssetsWithdrawn(account_, withdrawnAssets_);
        }

        // Transfer the shares to the account.
        if (reclaimedShares_ != 0) {
            require(ERC20Helper.transfer(pool, account_, reclaimedShares_), "WM:WAU:TRANSFER_FAIL");
            emit SharesUnlocked(account_, reclaimedShares_);
        }
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    // TODO: Use timestamps instead of periods for measuring time.

    function _getPeriod(uint256 time_) internal view returns (uint256 period_) {
        period_ = time_ <= periodStart ? 0 : (time_ - periodStart) / periodFrequency;
    }

    function _getWithdrawalPeriodBounds(uint256 period_) internal view returns (uint256 start_, uint256 end_) {
        start_ = periodStart + period_ * periodFrequency;
        end_   = start_ + periodDuration;
    }

    function _getWithdrawalPeriods(address account_) internal view returns (uint256 currentPeriod_, uint256 nextPeriod_) {
        // Fetch the current withdrawal period for the account, and calculate the next available one.
        currentPeriod_ = requests[account_].withdrawalPeriod;
        nextPeriod_    = _getPeriod(block.timestamp + periodCooldown);
    }

    function _isWithinCooldown(address account_) internal view returns (bool isWithinCooldown_) {
        isWithinCooldown_ = _getPeriod(block.timestamp) < requests[account_].withdrawalPeriod;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    // TODO: Check if all these view functions are needed, or can return structs directly.
    // TODO: Discuss what naming convention to use for fixing duplicate names of local variabes and function names.

    function availableAssets(uint256 period_) external override view returns (uint256 availableAssets_) {
        availableAssets_ = periodStates[period_].availableAssets;
    }

    function factory() external view override returns (address factory_) {
        return _factory();
    }

    function implementation() external view override returns (address implementation_) {
        return _implementation();
    }

    function isProcessed(uint256 period_) external override view returns (bool isProcessed_) {
        isProcessed_ = periodStates[period_].isProcessed;
    }

    function leftoverShares(uint256 period_) external override view returns (uint256 leftoverShares_) {
        leftoverShares_ = periodStates[period_].leftoverShares;
    }

    function lockedShares(address account_) external override view returns (uint256 lockedShares_) {
        lockedShares_ = requests[account_].lockedShares;
    }

    function pendingWithdrawals(uint256 period_) external override view returns (uint256 pendingWithdrawals_) {
        pendingWithdrawals_ = periodStates[period_].pendingWithdrawals;
    }

    function totalShares(uint256 period_) external override view returns (uint256 totalShares_) {
        totalShares_ = periodStates[period_].totalShares;
    }

    function withdrawalPeriod(address account_) external override view returns (uint256 withdrawalPeriod_) {
        withdrawalPeriod_ = requests[account_].withdrawalPeriod;
    }

}
