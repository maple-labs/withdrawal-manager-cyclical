// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IWithdrawalManagerStorage {

    /**
     *  @dev    Retrieves the asset for the withdrawal manager.
     *  @return asset_ The address of the asset.
     */
    function asset() external view returns (address asset_);

    /**
     *  @dev    Get the configuration for id.
     *  @param  id_                       The id/index for the configuration to be fetched.
     *  @return startingCycleId_          The starting index of the cycle that the configuration is valid from.
     *  @return startingTime_             The starting timestamp that the configuration is valid from.
     *  @return withdrawalWindowDuration_ The amount of seconds in the withdrawal window.
     *  @return cycleDuration_            The amount of seconds for a full cycle duration.
     */
    function configurations(uint256 id_) external view returns (uint64 startingCycleId_, uint64 startingTime_, uint64 withdrawalWindowDuration_, uint64 cycleDuration_);

     /**
     *  @dev    Get state for a given withdrawal cycle.
     *  @param  cycleId_          The id/index for the cycle to check.
     *  @return totalShares_      The amount of shares elected to withdraw in this cycle.
     *  @return pendingWithdrawal The number of withdrawal requests in this cycle.
     *  @return availableAssets_  The total amount of assets in the withdrawal cycle.
     *  @return leftoverShares_   The amount of shares yet to be withdrawn in the cycle.
     *  @return isProcessed_      A boolean indication whether this cycle has been processed.
     */
    function cycleStates(uint256 cycleId_) external view returns (uint256 totalShares_, uint256 pendingWithdrawal, uint256 availableAssets_, uint256 leftoverShares_, bool isProcessed_);

    /**
     *  @dev    Retrieves the pool for the withdrawal manager.
     *  @return pool_ The address of the pool.
     */
    function pool() external view returns (address pool_);

    /**
     *  @dev    Retrieves the pool manager for the withdrawal manager.
     *  @return poolManager_ The address of the poolManager_.
     */
    function poolManager() external view returns (address poolManager_);

     /**
     *  @dev    Get a withdrawal request from a user.
     *  @param  user_             The address of the user to check.
     *  @return lockedShares_     The total mount of shares elected to withdraw.
     *  @return withdrawalPeriod_ The index of the cycle that this user can withdraw.
     */
    function requests(address user_) external view returns (uint256 lockedShares_, uint256 withdrawalPeriod_);

}
