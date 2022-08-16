// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

abstract contract WithdrawalManagerStorage {

    address public pool;
    address public poolManager;

    uint256 public latestConfigId;

    mapping(address => uint256) public exitCycleId;
    mapping(address => uint256) public lockedShares;

    mapping(uint256 => uint256) public totalCycleShares;

    mapping(uint256 => CycleConfig) public cycleConfigs;

    struct CycleConfig {
        uint64 initialCycleId;    // Identifier of the first withdrawal cycle using this configuration.
        uint64 initialCycleTime;  // Timestamp of the first withdrawal cycle using this configuration.
        uint64 cycleDuration;     // Duration of the withdrawal cycle.
        uint64 windowDuration;    // Duration of the withdrawal window.
    }

}
