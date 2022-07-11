// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IWithdrawalManagerStorage {

    function asset() external view returns (address asset_);

    // Amount of time before shares become eligible for withdrawal. TODO: Remove in a separate PR.
    function cooldown() external view returns (uint256 cooldown_);

    function periodDuration() external view returns (uint256 periodFrequency_);

    // Beginning of the first withdrawal period.
    function periodStart() external view returns (uint256 periodStart_);

    function periodStates(uint256 periodId_) external view returns (uint256 totalShares_, uint256 pendingWithdrawal, uint256 availableAssets_, uint256 leftoverShares_, bool isProcessed_);

    // Instance of a v2 pool.
    function pool() external view returns (address pool_);

    function poolManager() external view returns (address poolManager_);

    function requests(address user_) external view returns (uint256 lockedShares_, uint256 withdrawalPeriod_); 

    // Duration of each withdrawal period.
    function withdrawalWindow() external view returns (uint256 periodDuration_);

}
