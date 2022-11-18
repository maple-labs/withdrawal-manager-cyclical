// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

import { IMapleGlobalsLike } from "./interfaces/Interfaces.sol";

contract WithdrawalManagerFactory is MapleProxyFactory {

    constructor(address globals_) MapleProxyFactory(globals_) {}

    function createInstance(bytes calldata arguments_, bytes32 salt_) public override(MapleProxyFactory) returns (address instance_) {
        require(IMapleGlobalsLike(mapleGlobals).isPoolDeployer(msg.sender), "WMF:CI:NOT_DEPLOYER");

        isInstance[instance_ = super.createInstance(arguments_, salt_)] = true;
    }

}
