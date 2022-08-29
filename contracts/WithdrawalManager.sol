// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { ERC20Helper }           from "../modules/erc20-helper/src/ERC20Helper.sol";
import { IMapleProxyFactory }    from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";
import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IERC20Like, IMapleGlobalsLike, IPoolLike, IPoolManagerLike } from "./interfaces/Interfaces.sol";

import { IWithdrawalManager } from "./interfaces/IWithdrawalManager.sol";

import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";

contract WithdrawalManager is IWithdrawalManager, WithdrawalManagerStorage, MapleProxiedInternals {

    /**
     *    **************************
     *    *** Withdrawal Manager ***
     *    **************************
     *    `cycleDuration` is the time of a full withdrawal cycle.
     *
     *    |--------|--------|
     *        C1       C2
     *
     *    There is a withdrawal window at the beginning of each withdrawal cycle.
     *
     *    |===-----|===-----|
     *     WW1      WW2
     *
     *    Once a user locks their shares, they must wait at least one full cycle from the end of the cycle they locked their shares in.
     *    Users are only able to withdraw during a withdrawal window, which starts at the beginning of each cycle.
     *
     *    |===-.---|===-----|===-----|
     *         ^             ^
     *     shares locked    earliest withdrawal time
     *
     *    When the pool delegate changes the configuration, it will take effect only on the start of the third cycle.
     *    This way all users that have already locked their shares will not have their withdrawal time affected.
     *
     *        C1       C2       C3             C4
     *    |===--.--|===-----|===-----|==========----------|
     *          ^                     ^
     *    configuration change     new configuration kicks in
     *
     *    Users that request a withdrawal during C1 will withdraw during WW3 using the old configuration.
     *    Users that lock their shares during and after C2 will withdraw in windows that use the new configuration.
     */

    /***********************/
    /*** Proxy Functions ***/
    /***********************/

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "WM:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "WM:M:FAILED");
    }

    function setImplementation(address implementation_) external override {
        require(msg.sender == _factory(), "WM:SI:NOT_FACTORY");
        _setImplementation(implementation_);
    }

    function upgrade(uint256 version_, bytes calldata arguments_) external override {
        require(msg.sender == admin(), "WM:U:NOT_ADMIN");

        IMapleGlobalsLike mapleGlobals = IMapleGlobalsLike(IPoolManagerLike(poolManager).globals());

        require(mapleGlobals.isValidScheduledCall(msg.sender, address(this), "WM:UPGRADE", msg.data), "WM:U:NOT_SCHEDULED");

        mapleGlobals.unscheduleCall(msg.sender, "WM:UPGRADE", msg.data);
        IMapleProxyFactory(_factory()).upgradeInstance(version_, arguments_);
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function setExitConfig(uint256 cycleDuration_, uint256 windowDuration_) external override {
        CycleConfig memory config_ = _getCurrentConfig();

        require(msg.sender == admin(),             "WM:SEC:NOT_ADMIN");
        require(windowDuration_ != 0,              "WM:SEC:ZERO_WINDOW");
        require(windowDuration_ <= cycleDuration_, "WM:SEC:WINDOW_OOB");

        require(
            cycleDuration_  != config_.cycleDuration ||
            windowDuration_ != config_.windowDuration,
            "WM:SEC:IDENTICAL_CONFIG"
        );

        // The new config will take effect only after the current cycle and two additional ones elapse.
        // This is done in order to to prevent overlaps between the current and new withdrawal cycles.
        uint256 initialCycleId_   = _getCurrentCycleId(config_) + 3;
        uint256 initialCycleTime_ = _getWindowStart(config_, initialCycleId_);

        // If the latest config has already started, add a new config.
        // Otherwise, the existing pending config will be overwritten.
        uint256 latestConfigId_ = latestConfigId;

        if (block.timestamp >= cycleConfigs[latestConfigId_].initialCycleTime) {
            latestConfigId_ = ++latestConfigId;
        }

        cycleConfigs[latestConfigId_] = CycleConfig({
            initialCycleId:   uint64(initialCycleId_),
            initialCycleTime: uint64(initialCycleTime_),
            cycleDuration:    uint64(cycleDuration_),
            windowDuration:   uint64(windowDuration_)
        });
    }

    /**********************/
    /*** Exit Functions ***/
    /**********************/

    // TODO: Add checks for protocol pause?

    function addShares(uint256 shares_, address owner_) external override {
        require(msg.sender == poolManager, "WM:AS:NOT_POOL_MANAGER");

        uint256 exitCycleId_  = exitCycleId[owner_];
        uint256 lockedShares_ = lockedShares[owner_];

        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);

        require(lockedShares_ == 0 || block.timestamp >= _getWindowStart(config_, exitCycleId_), "WM:AS:WITHDRAWAL_PENDING");

        // Remove all existing shares from the current cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        lockedShares_ += shares_;

        require(lockedShares_ != 0, "WM:AS:NO_OP");

        // Move all shares (including any new ones) to the new cycle.
        exitCycleId_ = _getCurrentCycleId(config_) + 2;
        totalCycleShares[exitCycleId_] += lockedShares_;

        exitCycleId[owner_]  = exitCycleId_;
        lockedShares[owner_] = lockedShares_;

        require(ERC20Helper.transferFrom(pool, msg.sender, address(this), shares_), "WM:AS:TRANSFER_FROM_FAIL");
    }

    function removeShares(uint256 shares_, address owner_) external override returns (uint256 sharesReturned_) {
        require(msg.sender == poolManager, "WM:RS:NOT_POOL_MANAGER");

        uint256 exitCycleId_  = exitCycleId[owner_];
        uint256 lockedShares_ = lockedShares[owner_];

        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);

        require(block.timestamp >= _getWindowStart(config_, exitCycleId_), "WM:RS:WITHDRAWAL_PENDING");
        require(shares_ != 0 && shares_ <= lockedShares_,                  "WM:RS:SHARES_OOB");

        // Remove shares from old the cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        // Calculate remaining shares and new cycle (if applicable).
        lockedShares_ -= shares_;
        exitCycleId_   = lockedShares_ != 0 ? _getCurrentCycleId(config_) + 2 : 0;

        // Add shares to new cycle (if applicable).
        if (lockedShares_ != 0) {
            totalCycleShares[exitCycleId_] += lockedShares_;
        }

        // Update the withdrawal request.
        exitCycleId[owner_]  = exitCycleId_;
        lockedShares[owner_] = lockedShares_;

        sharesReturned_ = shares_;

        require(ERC20Helper.transfer(pool, owner_, shares_), "WM:RS:TRANSFER_FAIL");
    }

    function processExit(address account_, uint256 requestedShares_) external override returns (uint256 redeemableShares_, uint256 resultingAssets_) {
        require(msg.sender == poolManager, "WM:PE:NOT_PM");

        uint256 exitCycleId_  = exitCycleId[account_];
        uint256 lockedShares_ = lockedShares[account_];

        require(requestedShares_ == lockedShares_, "WM:PE:INVALID_SHARES");

        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);

        bool partialLiquidity_;

        ( redeemableShares_, resultingAssets_, partialLiquidity_ ) = _previewRedeem(account_, lockedShares_, exitCycleId_, config_);

        // Transfer both returned shares and redeemable shares, burn only the redeemable shares in the pool.
        require(ERC20Helper.transfer(pool, account_, redeemableShares_), "WM:PE:TRANSFER_FAIL");

        // Reduce totalCurrentShares by the shares that were used in the old cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        // Reduce the locked shares by the total amount transferred back to the LP.
        lockedShares_ -= redeemableShares_;

        // If there are any remaining shares, move them to the next cycle.
        // In case of partial liquidity move shares only one cycle forward (instead of two).
        if (lockedShares_ != 0) {
            exitCycleId_ = _getCurrentCycleId(config_) + (partialLiquidity_ ? 1 : 2);
            totalCycleShares[exitCycleId_] += lockedShares_;
        } else {
            exitCycleId_ = 0;
        }

        // Update the locked shares and cycle for the account, setting to zero if no shares are remaining.
        lockedShares[account_] = lockedShares_;
        exitCycleId[account_]  = exitCycleId_;
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _getConfigAtId(uint256 cycleId_) internal view returns (CycleConfig memory config_) {
        uint256 configId_ = latestConfigId;

        if (configId_ == 0) return cycleConfigs[configId_];

        while (cycleId_ < cycleConfigs[configId_].initialCycleId) {
            --configId_;
        }

        config_ = cycleConfigs[configId_];
    }

    function _getCurrentConfig() internal view returns (CycleConfig memory config_) {
        uint256 configId_ = latestConfigId;

        while (block.timestamp < cycleConfigs[configId_].initialCycleTime) {
            configId_--;
        }

        config_ = cycleConfigs[configId_];
    }

    function _getCurrentCycleId(CycleConfig memory config_) internal view returns (uint256 cycleId_) {
        cycleId_ = config_.initialCycleId + (block.timestamp - config_.initialCycleTime) / config_.cycleDuration;
    }

    function _getRedeemableAmounts(uint256 lockedShares_, address owner_) internal view returns (uint256 redeemableShares_, uint256 resultingAssets_, bool partialLiquidity_) {
        IPoolManagerLike poolManager_ = IPoolManagerLike(poolManager);

        // Calculate how much liquidity is available, and how much is required to allow redemption of shares.
        uint256 availableLiquidity_      = IERC20Like(asset()).balanceOf(pool);
        uint256 totalAssetsWithLosses_   = poolManager_.totalAssets() - poolManager_.unrealizedLosses();
        uint256 totalSupply_             = IPoolLike(pool).totalSupply();
        uint256 totalRequestedLiquidity_ = totalCycleShares[exitCycleId[owner_]] * totalAssetsWithLosses_ / totalSupply_;

        partialLiquidity_ = availableLiquidity_ < totalRequestedLiquidity_;

        // Calculate maximum redeemable shares while maintaining a pro-rata distribution.
        redeemableShares_ =
            partialLiquidity_
                ? lockedShares_ * availableLiquidity_ / totalRequestedLiquidity_
                : lockedShares_;

        resultingAssets_ = totalAssetsWithLosses_ * redeemableShares_ / totalSupply_;
    }

    function _getWindowStart(CycleConfig memory config_, uint256 cycleId_) internal pure returns (uint256 cycleStart_) {
        cycleStart_ = config_.initialCycleTime + (cycleId_ - config_.initialCycleId) * config_.cycleDuration;
    }

    function _previewRedeem(
        address owner_,
        uint256 lockedShares_,
        uint256 exitCycleId_,
        CycleConfig memory config_
    )
        internal view returns (uint256 redeemableShares_, uint256 resultingAssets_, bool partialLiquidity_)
    {
        require(lockedShares_ != 0, "WM:PR:NO_REQUEST");

        uint256 windowStart_ = _getWindowStart(config_, exitCycleId_);

        require(
            block.timestamp >= windowStart_ &&
            block.timestamp < windowStart_ + config_.windowDuration,
            "WM:PR:NOT_IN_WINDOW"
        );

        ( redeemableShares_, resultingAssets_, partialLiquidity_ ) = _getRedeemableAmounts(lockedShares_, owner_);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function admin() public view override returns (address admin_) {
        admin_ = IPoolManagerLike(poolManager).admin();
    }

    function asset() public view override returns (address asset_) {
        asset_ = IPoolLike(pool).asset();
    }

    function factory() external view override returns (address factory_) {
        factory_ = _factory();
    }

    function implementation() external view override returns (address implementation_) {
        implementation_ = _implementation();
    }

    function isInExitWindow(address owner_) external view override returns (bool isInExitWindow_) {
        uint256 exitCycleId_       = exitCycleId[owner_];
        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);
        uint256 windowStart_       = _getWindowStart(config_, exitCycleId_);
        isInExitWindow_            = block.timestamp >= windowStart_ && block.timestamp < windowStart_ + config_.windowDuration;
    }

    function lockedLiquidity() external view override returns (uint256 lockedLiquidity_) {
        CycleConfig memory config_ = _getCurrentConfig();

        uint256 exitCycleId_ = _getCurrentCycleId(config_);
        uint256 windowStart_ = _getWindowStart(config_, exitCycleId_);
        uint256 windowEnd_   = windowStart_ + config_.windowDuration;

        if (block.timestamp >= windowStart_ && block.timestamp < windowEnd_) {
            IPoolManagerLike poolManager_  = IPoolManagerLike(poolManager);
            uint256 totalAssetsWithLosses_ = poolManager_.totalAssets() - poolManager_.unrealizedLosses();
            uint256 totalSupply_           = IPoolLike(pool).totalSupply();

            lockedLiquidity_ = totalCycleShares[exitCycleId_] * totalAssetsWithLosses_ / totalSupply_;
        }
    }

    function previewRedeem(address owner_, uint256 shares_) external view override returns (uint256 redeemableShares_, uint256 resultingAssets_) {
        uint256 exitCycleId_ = exitCycleId[owner_];

        require(shares_ == lockedShares[owner_], "WM:PE:INVALID_SHARES");

        ( redeemableShares_, resultingAssets_, ) = _previewRedeem(owner_, shares_, exitCycleId_, _getConfigAtId(exitCycleId_));
    }

}
