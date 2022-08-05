// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

contract WithdrawalManagerFactory is MapleProxyFactory {

    mapping(address => bool) public isInstance;

    constructor(address globals_) MapleProxyFactory(globals_) {}

    function createInstance(bytes calldata arguments_, bytes32 salt_) public override(MapleProxyFactory) returns (address instance_) {
        isInstance[instance_ = super.createInstance(arguments_, salt_)] = true;
    }

}
