// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IWithdrawalManagerStorage } from "./interfaces/IWithdrawalManagerStorage.sol";

abstract contract WithdrawalManagerStorage is IWithdrawalManagerStorage {

    // Contract dependencies.
    address public override asset;        // Underlying liquidity asset.
    address public override pool;         // Instance of a v2 pool.
    address public override poolManager;  // Pool's manager contract.

    uint256 _currentConfigId; // Current valid configuration

    mapping(address => WithdrawalRequest) public override requests;

    // The mapping key is the index of the withdrawal period (starting from 0).
    // TODO: Replace period keys with timestamp keys.
    mapping(uint256 => WithdrawalCycleState) public override cycleStates;

    mapping(uint256 => Configuration) public override configurations;

    struct WithdrawalRequest {
        uint256 lockedShares;       // Amount of shares that have been locked by an account.
        uint256 withdrawalCycleId;  // Index of the pending withdrawal period.
    }

    struct WithdrawalCycleState {
        uint256 totalShares;         // Total amount of shares that have been locked into this withdrawal period.
                                     // This value does not change after shares are redeemed for assets.
        uint256 pendingWithdrawals;  // Number of accounts that have yet to withdraw from this withdrawal period. Used to collect dust on the last withdrawal.
        uint256 availableAssets;     // Current amount of assets available for withdrawal. Decreases after an account performs a withdrawal.
        uint256 leftoverShares;      // Current amount of shares available for unlocking. Decreases after an account unlocks them.
        bool    isProcessed;         // Defines if the shares belonging to this withdrawal period have been processed.
    }

    struct Configuration {
        uint64 startingCycleId;
        uint64 startingTime;
        uint64 withdrawalWindowDuration;
        uint64 cycleDuration;
    }

}
