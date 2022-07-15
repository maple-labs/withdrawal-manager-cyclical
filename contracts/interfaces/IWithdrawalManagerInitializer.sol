// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

/// @title Initializes a WithdrawalManager.
interface IWithdrawalManagerInitializer {

    /**
     *  @dev    Encode the arguments to pass to the initializer.
     *  @param  asset_                    The address of the asset for the withdrawal manager.
     *  @param  pool_                     The address of the pool to withdraw from.
     *  @param  cycleStart_               The initial timestamp for the intial configuration.
     *  @param  withdrawalWindowDuration_ The amount of seconds in the withdraw window for the initial configuration.
     *  @param  cycleDuration_            The duration, in seconds, of each withdrawal cycle.
     *  @return encodedArguments_         A bytes array of the encoded arguments.
     */
    function encodeArguments(
        address asset_,
        address pool_,
        uint256 cycleStart_,
        uint256 withdrawalWindowDuration_,
        uint256 cycleDuration_
    ) external pure returns (bytes memory encodedArguments_);

    /**
     *  @dev    Encode the arguments to pass to the initializer.
     *  @param  encodedArguments_         A bytes array of the encoded arguments.
     *  @return asset_                    The address of the asset for the withdrawal manager.
     *  @return pool_                     The address of the pool to withdraw from.
     *  @return cycleStart_               The initial timestamp for the intial configuration.
     *  @return withdrawalWindowDuration_ The amount of seconds in the withdraw window for the initial configuration.
     *  @return cycleDuration_            The duration, in seconds, of each withdrawal cycle.
     */
    function decodeArguments(bytes calldata encodedArguments_)
        external pure returns (
            address asset_,
            address pool_,
            uint256 cycleStart_,
            uint256 withdrawalWindowDuration_,
            uint256 cycleDuration_
        );

}
