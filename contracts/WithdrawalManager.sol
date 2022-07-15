// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { console } from "../modules/contract-test-utils/contracts/test.sol";

import { ERC20Helper }        from "../modules/erc20-helper/src/ERC20Helper.sol";
import { IMapleProxyFactory } from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike, IPoolManagerLike } from "./interfaces/Interfaces.sol";
import { IWithdrawalManager }          from "./interfaces/IWithdrawalManager.sol";

import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";

// TODO: Reduce error message lengths / use custom errors.
// TODO: Optimize storage use, investigate struct assignment.
// TODO: Check gas usage and contract size.

/// @title Manages the withdrawal requests of a liquidity pool.
contract WithdrawalManager is IWithdrawalManager, WithdrawalManagerStorage, MapleProxiedInternals {

    /**
     *    TODO: Add title
     *    `cycleDuration` is the time of a full cycle.
     *    |--------|--------|
     *        C1       C2
     *
     *    Within a cycle, there's a withdrawal window, always at the start.
     *    |===-----|===-----|
     *     WW1      WW2
     *
     *    Once a user locks their share, they must wait at least one full cycle from the end of the cycle they locked their shares in.
     *    Users are only able to withdraw during a withdrawal window, which starts at the beginning of each cycle.
     *    |===-.---|===-----|===-----|
     *         ^             ^
     *     shares locked    earliest withdrawal time
     *
     *    When PD changes the configuration, it'll take effect only on the start of the third cycle,
     *    so no user that locked their shares will have their withdrawal time affected.
     *        C1       C2       C3             C4
     *    |===--.--|===-----|===-----|==========----------|
     *          ^                     ^
     *    configuration change     new configuration kicks in
     *
     *    Although the configuration only changes in C4, users that lock their shares during C2 and C3, will
     *    withdraw according to the updated schedule. Users that request on C1, will withdraw on C3 according to the old configuration.
     */

    /**************************/
    /*** External Functions ***/
    /**************************/

    /// @dev Sets the valid parameters only for the next configuration. If there's no configuration
    /// lined up, it'll create one, otherwise it'll adjust the parameters.
    function setNextConfiguration(uint256 cycleDuration_, uint256 withdrawalWindowDuration_) external override {
        require(msg.sender == _admin(),                      "WM:SNC:NOT_ADMIN");
        require(withdrawalWindowDuration_ <= cycleDuration_, "WM:SNC:OOB");

        uint256 currentConfigId_ = _currentConfigId;
        uint256 currentCycleId_  = getCycleId(block.timestamp);

        ( , uint256 endOfCurrentCycleId_ ) = getCycleBounds(currentCycleId_);

        // To not affect any users that are currently withdrawing, two full cycles must elapse with no effect.
        // TODO: Why do we need cycle ID and starting time?
        // TODO: Investigate moving withdrawal windows to be at the end of the cycle.
        uint256 newConfigStartingTime_ = endOfCurrentCycleId_ + 2 * cycleDuration();

        // If there's no configuration lined up, incement the config count.
        // If the current config start time is in the future, it'll be overwritten at the _currentConfigId index.
        if (block.timestamp > configurations[_currentConfigId].startingTime) {
            currentConfigId_ = ++_currentConfigId;
        }

        configurations[currentConfigId_] = Configuration({
            startingCycleId:          uint64(currentCycleId_ + 3),
            startingTime:             uint64(newConfigStartingTime_),
            cycleDuration:            uint64(cycleDuration_),
            withdrawalWindowDuration: uint64(withdrawalWindowDuration_)
        });

    }

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
        ( uint256 currentCycleId, uint256 nextCycleId ) = _getWithdrawalCycleIds(msg.sender);

        // Update the request and all affected period states.
        _updateRequest(msg.sender, totalShares_, nextCycleId);
        _updateCycleState(totalShares_ - sharesToLock_, totalShares_, currentCycleId, nextCycleId);
    }

    // TODO: Check if ACL should be used here.
    function processCycle() external override {
        // Check if the current period has already been processed.
        uint256 cycleId_ = getCycleId(block.timestamp);
        require(!cycleStates[cycleId_].isProcessed, "WM:PC:DOUBLE_PROCESS");

        ( , uint256 cycleEnd ) = getWithdrawalWindowBounds(cycleId_);
        _processCycle(cycleId_, cycleEnd);
    }

    function reclaimAssets(uint256 cycleId_) external override returns (uint256 reclaimedAssets_) {
        // Reclaiming can only be performed by the pool delegate.
        require(msg.sender == IPoolLike(pool).poolDelegate(), "WM:RA:NOT_PD");

        // Assets can be reclaimed only after the withdrawal period has elapsed.
        ( , uint256 cycleEnd ) = getWithdrawalWindowBounds(cycleId_);
        require(block.timestamp >= cycleEnd, "WM:RA:EARLY_RECLAIM");

        WithdrawalCycleState storage cycleState = cycleStates[cycleId_];

        // Check if there are any assets that have not been withdrawn yet.
        reclaimedAssets_ = cycleState.availableAssets;
        require(reclaimedAssets_ != 0, "WM:RA:ZERO_ASSETS");

        // Deposit all available assets back into the pool.
        require(ERC20Helper.approve(address(asset), address(pool), reclaimedAssets_), "WM:RA:APPROVE_FAIL");

        // TODO: Is using the deposit function the best approach? Check how deposit is implemented in PoolV2 later and what could go wrong here.
        uint256 mintedShares = IPoolLike(pool).deposit(reclaimedAssets_, address(this));

        // Increase the number of leftover shares by the amount that was minted.
        cycleState.leftoverShares += mintedShares;  // TODO: Check if this causes conflicts with existing leftover shares.
        cycleState.availableAssets = 0;

        emit AssetsReclaimed(cycleId_, reclaimedAssets_);
    }

    function redeemPosition(uint256 sharesToReclaim_) external override returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 reclaimedShares_) {
        // Check if a withdrawal request was made.
        uint256 personalShares = requests[msg.sender].lockedShares;
        require(personalShares != 0, "WM:RP:NO_REQUEST");

        // Get the current and next available withdrawal period.
        // TODO: Change currentCycle
        ( uint256 currentCycle, uint256 nextCycle ) = _getWithdrawalCycleIds(msg.sender);

        // Get the start and end of the current withdrawal period.
        ( uint256 cycleStart_, uint256 cycleEnd ) = getWithdrawalWindowBounds(currentCycle);

        require(block.timestamp >= cycleStart_, "WM:RP:EARLY_WITHDRAW");

        // If the period has not been processed yet, do so before the withdrawal.
        if (!cycleStates[currentCycle].isProcessed) {
            _processCycle(currentCycle, cycleEnd);
        }

        ( withdrawnAssets_, redeemedShares_, reclaimedShares_ ) = _withdrawAndUnlock(msg.sender, sharesToReclaim_, personalShares, currentCycle);

        // Update the request and the state of all affected withdrawal periods.
        uint256 remainingShares = personalShares - redeemedShares_ - reclaimedShares_;
        _updateRequest(msg.sender, remainingShares, nextCycle);
        _updateCycleState(personalShares, remainingShares, currentCycle, nextCycle);
    }

    function unlockShares(uint256 sharesToReclaim_) external override returns (uint256 remainingShares_) {
        // Transfer the requested amount of shares to the account.
        remainingShares_ = _unlockShares(msg.sender, sharesToReclaim_);

        // Get the current and next available withdrawal period.
        ( uint256 currentCycle, uint256 nextCycle ) = _getWithdrawalCycleIds(msg.sender);

        // Update the request and all affected period states.
        _updateRequest(msg.sender, remainingShares_, nextCycle);
        _updateCycleState(remainingShares_ + sharesToReclaim_, remainingShares_, currentCycle, nextCycle);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _admin() internal view returns (address admin_) {
        admin_ = IPoolManagerLike(poolManager).admin();
    }

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

    function _moveCycleShares(uint256 cycleId_, uint256 nextCycleId_, uint256 currentShares_, uint256 nextShares_) internal {
        // If the account already has locked shares, remove them from the current period.
        if (currentShares_ != 0) {
            cycleStates[cycleId_].totalShares        -= currentShares_;
            cycleStates[cycleId_].pendingWithdrawals -= 1;
        }

        // Add shares into the next period if necessary.
        if (nextShares_ != 0) {
            cycleStates[nextCycleId_].totalShares        += nextShares_;
            cycleStates[nextCycleId_].pendingWithdrawals += 1;
        }
    }

    function _processCycle(uint256 cycleId_, uint256 cycleEnd) internal {
        WithdrawalCycleState storage cycleState = cycleStates[cycleId_];

        // If the withdrawal period elapsed, perform no redemption of shares.
        if (block.timestamp >= cycleEnd) {
            cycleState.leftoverShares = cycleState.totalShares;
            cycleState.isProcessed    = true;
            return;
        }

        uint256 totalShares_     = IPoolLike(pool).maxRedeem(address(this));
        uint256 cycleShares      = cycleState.totalShares;
        uint256 redeemableShares = totalShares_ > cycleShares ? cycleShares : totalShares_;

        // Calculate amount of available assets and leftover shares.
        uint256 availableAssets_ = redeemableShares > 0 ? IPoolManagerLike(poolManager).redeem(redeemableShares, address(this), address(this)) : 0;
        uint256 leftoverShares_  = cycleShares - redeemableShares;

        // Update the withdrawal period state.
        cycleState.availableAssets = availableAssets_;
        cycleState.leftoverShares  = leftoverShares_;
        cycleState.isProcessed     = true;

        emit CycleProcessed(cycleId_, availableAssets_, leftoverShares_);
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
    function _updateCycleShares(uint256 cycleId_, uint256 currentShares_, uint256 nextShares_) internal {
        // If additional shares were locked, increase the amount of total shares locked in the period.
        if (nextShares_ > currentShares_) {
            cycleStates[cycleId_].totalShares += nextShares_ - currentShares_;
        }
        // If shares were unlocked, decrease the amount of total shares locked in the period.
        else {
            cycleStates[cycleId_].totalShares -= currentShares_ - nextShares_;
        }

        // If the account has no remaining shares, decrease the number of withdrawal requests.
        if (nextShares_ == 0) {
            cycleStates[cycleId_].pendingWithdrawals -= 1;
        }
    }

    function _updateCycleState(uint256 currentShares_, uint256 nextShares_, uint256 currentCycleId_, uint256 nextCycleId_) internal {
        // If shares do not need to be moved across withdrawal periods, just update the amount of shares.
        if (currentCycleId_ == nextCycleId_) {
            _updateCycleShares(nextCycleId_, currentShares_, nextShares_);
        }
        // If the next period is different, move all the shares from the current period to the new one.
        else {
            _moveCycleShares(currentCycleId_, nextCycleId_, currentShares_, nextShares_);
        }
    }

    function _updateRequest(address account_, uint256 shares_, uint256 cycleId_) internal {
        // If any shares are remaining, perform the update.
        if (shares_ != 0) {
            requests[account_] = WithdrawalRequest({ lockedShares: shares_, withdrawalCycleId: cycleId_ });
            emit WithdrawalPending(account_, cycleId_);
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
        uint256 cycleId_
    )
        internal returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 reclaimedShares_)
    {
        // Cache variables.
        WithdrawalCycleState storage cycleState = cycleStates[cycleId_];
        uint256 activeShares     = cycleState.totalShares;
        uint256 availableAssets_ = cycleState.availableAssets;
        uint256 leftoverShares_  = cycleState.leftoverShares;
        uint256 accountCount     = cycleState.pendingWithdrawals;

        // [personalShares / activeShares] is the percentage of the assets / shares in the withdrawal period that the account is entitled to claim.
        // Multiplying this amount by the amount of leftover shares and available assets calculates his "fair share".
        withdrawnAssets_          = accountCount > 1 ? availableAssets_ * personalShares_ / activeShares : availableAssets_;
        uint256 reclaimableShares = accountCount > 1 ? leftoverShares_ * personalShares_ / activeShares : leftoverShares_;

        // Remove the entitled assets and shares from the withdrawal period.
        cycleState.availableAssets -= withdrawnAssets_;
        cycleState.leftoverShares  -= reclaimableShares;

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

    /// @dev Returns the valid configuration for a given timestamp
    function _getConfigIdAtTimestamp(uint256 timestamp_) internal view returns (uint256 configId_) {
        configId_ = _currentConfigId;
        while (true) {
            Configuration memory config_ = configurations[configId_];

            // If timestamp is before start of config, decrement configId.
            if (timestamp_ < config_.startingTime) {
                // TODO revisit to check if return 0 or revert.
                if (configId_ == 0) return 0;
                configId_--;
                continue;
            }

           return configId_;
        }
    }

    function _getConfigIdAtCycleId(uint256 cycleId_) internal view returns (uint256 configId_) {
        configId_ = _currentConfigId;
        while (true) {
            Configuration memory config_ = configurations[configId_];

            if (cycleId_ < config_.startingCycleId) {

                // TODO revisit to check if return 0 or revert.
                if (configId_ == 0) return 0;
                configId_--;
                continue;
            }

            return configId_;
        }
    }

    function _getWithdrawalCycleIds(address account_) internal view returns (uint256 currentCycleId_, uint256 nextCycleId_) {
        // Fetch the current withdrawal period for the account, and calculate the next available one.
        currentCycleId_ = requests[account_].withdrawalCycleId;
        nextCycleId_    = getCycleId(block.timestamp) + 2;      // Need to wait for the current cycle to finish + 1 full cycle, hence the 2 is used.
    }

    function _isWithinCooldown(address account_) internal view returns (bool isWithinCooldown_) {
        isWithinCooldown_ = getCycleId(block.timestamp) < requests[account_].withdrawalCycleId;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    // TODO: Check if all these view functions are needed, or can return structs directly.
    // TODO: Discuss what naming convention to use for fixing duplicate names of local variabes and function names.

    function availableAssets(uint256 cycleId_) external override view returns (uint256 availableAssets_) {
        availableAssets_ = cycleStates[cycleId_].availableAssets;
    }

    function cycleDuration() public view override returns (uint256 periodDuration_) {
        periodDuration_ = configurations[_getConfigIdAtTimestamp(block.timestamp)].cycleDuration;
    }

    function factory() external view override returns (address factory_) {
        return _factory();
    }

    function getCycleId(uint256 timestamp_) public view override returns (uint256 cycleId_) {
        Configuration memory config_ = configurations[_getConfigIdAtTimestamp(timestamp_)];

        cycleId_ = config_.startingCycleId + ((timestamp_ - config_.startingTime) / config_.cycleDuration);
    }

    function getCycleBounds(uint256 cycleId_) public view override returns (uint256 start_, uint256 end_) {
        Configuration memory config_ = configurations[_getConfigIdAtCycleId(cycleId_)];

        start_ = config_.startingTime + (cycleId_ - config_.startingCycleId) * config_.cycleDuration;
        end_   = start_ + config_.cycleDuration;
    }

    function getWithdrawalWindowBounds(uint256 cycleId_) public view override returns (uint256 start_, uint256 end_) {
        Configuration memory config_ = configurations[_getConfigIdAtCycleId(cycleId_)];

        start_ = config_.startingTime + (cycleId_ - config_.startingCycleId) * config_.cycleDuration;
        end_   = start_ + config_.withdrawalWindowDuration;
    }

    function implementation() external view override returns (address implementation_) {
        return _implementation();
    }

    function isProcessed(uint256 cycleId_) external override view returns (bool isProcessed_) {
        isProcessed_ = cycleStates[cycleId_].isProcessed;
    }

    function leftoverShares(uint256 cycleId_) external override view returns (uint256 leftoverShares_) {
        leftoverShares_ = cycleStates[cycleId_].leftoverShares;
    }

    function lockedShares(address account_) external override view returns (uint256 lockedShares_) {
        lockedShares_ = requests[account_].lockedShares;
    }

    function pendingWithdrawals(uint256 cycleId_) external override view returns (uint256 pendingWithdrawals_) {
        pendingWithdrawals_ = cycleStates[cycleId_].pendingWithdrawals;
    }

    function totalShares(uint256 cycleId_) external override view returns (uint256 totalShares_) {
        totalShares_ = cycleStates[cycleId_].totalShares;
    }

    function withdrawalCycleId(address account_) external override view returns (uint256 withdrawalCycleId_) {
        withdrawalCycleId_ = requests[account_].withdrawalCycleId;
    }

    function withdrawalWindowDuration() external override view returns (uint256 withdrawalWindow_) {
        withdrawalWindow_ =  configurations[_getConfigIdAtTimestamp(block.timestamp)].withdrawalWindowDuration;
    }
}
