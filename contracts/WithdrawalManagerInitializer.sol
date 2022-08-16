// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike } from "./interfaces/Interfaces.sol";

import { WithdrawalManagerStorage } from "./WithdrawalManagerStorage.sol";

contract WithdrawalManagerInitializer is WithdrawalManagerStorage, MapleProxiedInternals {

    fallback() external {
        (
            address pool_,
            uint256 cycleDuration_,
            uint256 windowDuration_
        ) = abi.decode(msg.data, (address, uint256, uint256));

        require(pool_           != address(0),     "WMI:ZERO_POOL");
        require(windowDuration_ != 0,              "WMI:ZERO_WINDOW");
        require(windowDuration_ <= cycleDuration_, "WMI:WINDOW_OOB");

        pool        = pool_;
        poolManager = IPoolLike(pool_).manager();

        cycleConfigs[0] = CycleConfig({
            initialCycleId:   1,
            initialCycleTime: uint64(block.timestamp),
            cycleDuration:    uint64(cycleDuration_),
            windowDuration:   uint64(windowDuration_)
        });
    }

}
