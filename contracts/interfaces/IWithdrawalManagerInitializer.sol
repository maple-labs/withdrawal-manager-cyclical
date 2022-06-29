// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

/// @title Initializes a WithdrawalManager.
interface IWithdrawalManagerInitializer {

    function encodeArguments(
        address asset_,
        address pool_,
        uint256 periodStart_,
        uint256 periodDuration_,
        uint256 periodFrequency_,
        uint256 cooldownMultiplier_
    ) external pure returns (bytes memory encodedArguments_);

    function decodeArguments(bytes calldata encodedArguments_)
        external pure returns (
            address asset_,
            address pool_,
            uint256 periodStart_,
            uint256 periodDuration_,
            uint256 periodFrequency_,
            uint256 cooldownMultiplier_
        );

}
