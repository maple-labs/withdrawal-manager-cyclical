// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { ERC20Helper }           from "../modules/erc20-helper/src/ERC20Helper.sol";
import { IMapleProxyFactory }    from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";
import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IERC20Like, IPoolLike, IPoolManagerLike } from "./interfaces/Interfaces.sol";

import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";

contract WithdrawalManager is WithdrawalManagerStorage, MapleProxiedInternals {

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

    function migrate(address migrator_, bytes calldata arguments_) external {
        require(msg.sender == _factory(),        "WM:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "WM:M:FAILED");
    }

    function setImplementation(address implementation_) external {
        require(msg.sender == _factory(), "WM:SI:NOT_FACTORY");

        _setImplementation(implementation_);
    }

    function upgrade(uint256 version_, bytes calldata arguments_) external {
        require(msg.sender == admin(), "WM:U:NOT_ADMIN");

        IMapleProxyFactory(_factory()).upgradeInstance(version_, arguments_);
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function setExitConfig(uint256 cycleDuration_, uint256 windowDuration_) external {
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

    function addShares(uint256 shares_) external {
        uint256 exitCycleId_  = exitCycleId[msg.sender];
        uint256 lockedShares_ = lockedShares[msg.sender];

        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);

        require(lockedShares_ == 0 || block.timestamp >= _getWindowStart(config_, exitCycleId_), "WM:AS:WITHDRAWAL_PENDING");

        // Remove all existing shares from the current cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        lockedShares_ += shares_;

        require(lockedShares_ != 0, "WM:AS:NO_OP");

        // Move all shares (including any new ones) to the new cycle.
        exitCycleId_ = _getCurrentCycleId(config_) + 2;
        totalCycleShares[exitCycleId_] += lockedShares_;

        exitCycleId[msg.sender]  = exitCycleId_;
        lockedShares[msg.sender] = lockedShares_;

        require(ERC20Helper.transferFrom(pool, msg.sender, address(this), shares_), "WM:AS:TRANSFER_FAIL");
    }

    function removeShares(uint256 shares_) external {
        uint256 exitCycleId_  = exitCycleId[msg.sender];
        uint256 lockedShares_ = lockedShares[msg.sender];

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
        exitCycleId[msg.sender]  = exitCycleId_;
        lockedShares[msg.sender] = lockedShares_;

        require(ERC20Helper.transfer(pool, msg.sender, shares_), "WM:RS:TRANSFER_FAIL");
    }

    function withdraw(address account_, uint256 maxSharesToRemove_) external returns (uint256 withdrawnAssets_) {
        uint256 exitCycleId_  = exitCycleId[account_];
        uint256 lockedShares_ = lockedShares[account_];

        CycleConfig memory config_ = _getConfigAtId(exitCycleId_);

        require(msg.sender == pool, "WM:W:NOT_POOL");
        require(lockedShares_ != 0, "WM:W:NO_REQUEST");

        uint256 windowStart_ = _getWindowStart(config_, exitCycleId_);

        require(
            block.timestamp >= windowStart_ &&
            block.timestamp < windowStart_ + config_.windowDuration,
            "WM:W:NOT_IN_WINDOW"
        );

        // Calculate how much liquidity is available, and how much is required to allow redemption of shares.
        uint256 availableLiquidity_ = IERC20Like(asset()).balanceOf(address(pool));
        uint256 requestedLiquidity_ = IPoolLike(pool).previewRedeem(lockedShares_);
        bool    partialLiquidity_   = availableLiquidity_ < requestedLiquidity_;

        // Redeem as many shares as possible while maintaining a pro-rata distribution.
        uint256 redeemableShares_ =
            partialLiquidity_
                ? lockedShares_ * availableLiquidity_ / requestedLiquidity_
                : lockedShares_;

        withdrawnAssets_ = IPoolLike(pool).redeem(redeemableShares_, account_, address(this));

        // Reduce totalCurrentShares by the shares that were used in the old cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        // Reduce the locked shares by the amount redeemed.
        lockedShares_ -= redeemableShares_;

        // Calculate maximum available shares to remove based on request.
        uint256 sharesToRemove_ = lockedShares_ < maxSharesToRemove_ ? lockedShares_ : maxSharesToRemove_;

        // Calculate the amount of locked shares that will remain after requested shares are removed.
        lockedShares_ -= sharesToRemove_;

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

        // Transfer the shares that were marked for removal to the account.
        require(ERC20Helper.transfer(pool, account_, sharesToRemove_), "WM:W:TRANSFER_FAIL");
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _getConfigAtId(uint256 cycleId_) internal view returns (CycleConfig memory config_) {
        uint256 configId_ = latestConfigId;

        if (configId_ == 0) return cycleConfigs[configId_];

        while (cycleId_ < cycleConfigs[configId_].initialCycleId) {
            configId_--;
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

    function _getWindowStart(CycleConfig memory config_, uint256 cycleId_) internal pure returns (uint256 cycleStart_) {
        cycleStart_ = config_.initialCycleTime + (cycleId_ - config_.initialCycleId) * config_.cycleDuration;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function admin() public view returns (address admin_) {
        admin_ = IPoolManagerLike(manager()).admin();
    }

    function asset() public view returns (address asset_) {
        asset_ = IPoolLike(pool).asset();
    }

    function factory() external view returns (address factory_) {
        factory_ = _factory();
    }

    function implementation() external view returns (address implementation_) {
        implementation_ = _implementation();
    }

    function manager() public view returns (address manager_) {
        manager_ = IPoolLike(pool).manager();
    }

}
