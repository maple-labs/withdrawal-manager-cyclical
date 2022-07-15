// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike }                     from "./interfaces/Interfaces.sol";
import { IWithdrawalManagerInitializer } from "./interfaces/IWithdrawalManagerInitializer.sol";

import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";

// TODO: Reduce error message lengths / use custom errors.
// TODO: Optimize storage use, investigate struct assignment.
// TODO: Check gas usage and contract size.

/// @title Initializes a WithdrawalManager.
contract WithdrawalManagerInitializer is IWithdrawalManagerInitializer, WithdrawalManagerStorage, MapleProxiedInternals {

    function encodeArguments(
        address asset_,
        address pool_,
        uint256 cycleStart_,
        uint256 withdrawalWindow_,
        uint256 cycleDuration_
    ) external pure override returns (bytes memory encodedArguments_) {
        return abi.encode(asset_, pool_, cycleStart_, withdrawalWindow_, cycleDuration_);
    }

    function decodeArguments(bytes calldata encodedArguments_)
        public pure override returns (
            address asset_,
            address pool_,
            uint256 cycleStart_,
            uint256 withdrawalWindow_,
            uint256 cycleDuration_
        )
    {
        (
            asset_,
            pool_,
            cycleStart_,
            withdrawalWindow_,
            cycleDuration_
        ) = abi.decode(encodedArguments_, (address, address, uint256, uint256, uint256));
    }

    fallback() external {
        (
            address asset_,
            address pool_,
            uint256 cycleStart_,
            uint256 withdrawalWindow_,
            uint256 cycleDuration_
        ) = decodeArguments(msg.data);

        _initialize(asset_, pool_, cycleStart_, withdrawalWindow_, cycleDuration_);
    }

    function _initialize(address asset_, address pool_, uint256 cycleStart_, uint256 withdrawalWindow_, uint256 cycleDuration_) internal {
        // TODO: Add other needed require checks.
        require(withdrawalWindow_ <= cycleDuration_, "WMI:I:OUT_OF_BOUNDS");

        asset = asset_;
        pool  = pool_;

        address poolManagerCache = poolManager = IPoolLike(pool_).manager();
        IPoolLike(pool_).approve(poolManagerCache, type(uint256).max);

        configurations[0] = Configuration({
            startingCycleId:          0,
            startingTime:             uint64(cycleStart_),
            cycleDuration:            uint64(cycleDuration_),
            withdrawalWindowDuration: uint64(withdrawalWindow_)
        });

    }

}
