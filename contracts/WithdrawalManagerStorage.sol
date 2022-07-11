// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IWithdrawalManagerStorage } from "./interfaces/IWithdrawalManagerStorage.sol";

abstract contract WithdrawalManagerStorage is IWithdrawalManagerStorage {

    // Contract dependencies.
    address public override asset;        // Underlying liquidity asset.
    address public override pool;         // Instance of a v2 pool.
    address public override poolManager;  // Pool's manager contract.

    // TODO: Allow updates of period / cooldown.
    /**
    *    Period Duration is the time of a full cycle
    *    |--------|--------| 
    *        P1       P2 
    *    
    *    Within a period cycle, there's the withdrawal window:
    *    |===-----|===-----|
    *     WW1      WW2
    *
    *    The cooldown is the minimum amount of time between locking shares and withdrawal. 
    *    However, if the the cooldown ends outside of a Withdrawal Window, the user needs to wai
    *    until the next window to be eligible to withdraw 
    * 
    */

    uint256 public override periodStart;      // Timestamp of the start of the first period.
    uint256 public override withdrawalWindow; // Time within a period that users can withdraw.
    uint256 public override periodDuration;   // The length of a period cycle.
    uint256 public override cooldown;         // Amount of time (usually a multiple of period duration) before shares become eligible for withdrawal. TODO: Remove in a separate PR.

    mapping(address => WithdrawalRequest) public override requests;

    // The mapping key is the index of the withdrawal period (starting from 0).
    // TODO: Replace period keys with timestamp keys.
    mapping(uint256 => WithdrawalPeriodState) public override periodStates;

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
    
}
