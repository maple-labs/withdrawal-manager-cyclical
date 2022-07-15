// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IWithdrawalManagerStorage {

    function asset() external view returns (address asset_);

    function configurations(uint256 id_) external view returns (uint64 startingCycleId_, uint64 startingTime_, uint64 withdrawalWindowDuration_, uint64 cycleDuration_);

    // Beginning of the first withdrawal period.
    function cycleStates(uint256 cycleId_) external view returns (uint256 totalShares_, uint256 pendingWithdrawal, uint256 availableAssets_, uint256 leftoverShares_, bool isProcessed_);

    // Instance of a v2 pool.
    function pool() external view returns (address pool_);

    function poolManager() external view returns (address poolManager_);

    function requests(address user_) external view returns (uint256 lockedShares_, uint256 withdrawalCycleId_); 

}
