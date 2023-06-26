// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IPoolLike }                          from "./interfaces/Interfaces.sol";
import { IMapleWithdrawalManagerInitializer } from "./interfaces/IMapleWithdrawalManagerInitializer.sol";

import { MapleWithdrawalManagerStorage } from "./MapleWithdrawalManagerStorage.sol";

contract MapleWithdrawalManagerInitializer is IMapleWithdrawalManagerInitializer, MapleWithdrawalManagerStorage, MapleProxiedInternals {

    fallback() external {
        ( address pool_, uint256 cycleDuration_, uint256 windowDuration_ ) = decodeArguments(msg.data);

        _initialize(pool_, cycleDuration_, windowDuration_);
    }

    function decodeArguments(bytes calldata encodedArguments_) public pure override
        returns (
            address pool_,
            uint256 cycleDuration_,
            uint256 windowDuration_
        )
    {
        ( pool_, cycleDuration_, windowDuration_ ) = abi.decode(encodedArguments_, (address, uint256, uint256));
    }

    function encodeArguments(
        address pool_,
        uint256 cycleDuration_,
        uint256 windowDuration_
    )
        public pure override returns (bytes memory encodedArguments_)
    {
        encodedArguments_ = abi.encode(pool_, cycleDuration_, windowDuration_);
    }

    function _initialize(address pool_, uint256 cycleDuration_, uint256 windowDuration_) internal {
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

        emit Initialized(pool_, cycleDuration_, windowDuration_);
        emit ConfigurationUpdated({
            configId_:         0,
            initialCycleId_:   1,
            initialCycleTime_: uint64(block.timestamp),
            cycleDuration_:    uint64(cycleDuration_),
            windowDuration_:   uint64(windowDuration_)
        });
    }

}
