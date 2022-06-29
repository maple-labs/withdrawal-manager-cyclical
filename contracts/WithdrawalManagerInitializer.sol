// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike }                     from "./interfaces/Interfaces.sol";
import { IWithdrawalManagerInitializer } from "./interfaces/IWithdrawalManagerInitializer.sol";

// TODO: Reduce error message lengths / use custom errors.
// TODO: Optimize storage use, investigate struct assignment.
// TODO: Check gas usage and contract size.

/// @title Initializes a WithdrawalManager.
contract WithdrawalManagerInitializer is IWithdrawalManagerInitializer, MapleProxiedInternals {

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
    address internal _asset;        // Underlying liquidity asset.
    address internal _pool;         // Instance of a v2 pool.
    address internal _poolManager;  // Pool's manager contract.

    // TODO: Allow updates of period / cooldown.
    uint256 internal _periodStart;      // Beginning of the first withdrawal period.
    uint256 internal _periodDuration;   // Duration of each withdrawal period.
    uint256 internal _periodFrequency;  // How frequently a withdrawal period occurs.
    uint256 internal _periodCooldown;   // Amount of time before shares become eligible for withdrawal. TODO: Remove in a separate PR.

    mapping(address => WithdrawalRequest) internal _requests;

    // The mapping key is the index of the withdrawal period (starting from 0).
    // TODO: Replace period keys with timestamp keys.
    mapping(uint256 => WithdrawalPeriodState) internal _periodStates;

    function encodeArguments(
        address asset_,
        address pool_,
        uint256 periodStart_,
        uint256 periodDuration_,
        uint256 periodFrequency_,
        uint256 cooldownMultiplier_
    ) external pure override returns (bytes memory encodedArguments_) {
        return abi.encode(asset_, pool_, periodStart_, periodDuration_, periodFrequency_, cooldownMultiplier_);
    }

    function decodeArguments(bytes calldata encodedArguments_)
        public pure override returns (
            address asset_,
            address pool_,
            uint256 periodStart_,
            uint256 periodDuration_,
            uint256 periodFrequency_,
            uint256 cooldownMultiplier_
        )
    {
        (
            asset_,
            pool_,
            periodStart_,
            periodDuration_,
            periodFrequency_,
            cooldownMultiplier_
        ) = abi.decode(encodedArguments_, (address, address, uint256, uint256, uint256, uint256));
    }

    fallback() external {
        (
            address asset,
            address pool,
            uint256 periodStart,
            uint256 periodDuration,
            uint256 periodFrequency,
            uint256 cooldownMultiplier
        ) = decodeArguments(msg.data);

        _initialize(asset, pool, periodStart, periodDuration, periodFrequency, cooldownMultiplier);
    }

    function _initialize(address asset_, address pool_, uint256 periodStart_, uint256 periodDuration_, uint256 periodFrequency_, uint256 cooldownMultiplier_) internal {
        // TODO: Add other needed require checks.
        require(periodDuration_ <= periodFrequency_, "WMI:I:OUT_OF_BOUNDS");
        require(cooldownMultiplier_ != 0,            "WMI:I:COOLDOWN_ZERO");

        _asset = asset_;
        _pool  = pool_;

        address poolManagerCache = _poolManager = IPoolLike(pool_).manager();
        IPoolLike(pool_).approve(poolManagerCache, type(uint256).max);

        _periodStart     = periodStart_;
        _periodDuration  = periodDuration_;
        _periodFrequency = periodFrequency_;
        _periodCooldown  = periodFrequency_ * cooldownMultiplier_;
    }

}
