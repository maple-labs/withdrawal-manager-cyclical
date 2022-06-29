// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IMapleProxyFactory, MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

import { IWithdrawalManagerFactory } from "./interfaces/IWithdrawalManagerFactory.sol";

/// @title WithdrawalManagerFactory deploys WithdrawalManager instances.
contract WithdrawalManagerFactory is IWithdrawalManagerFactory, MapleProxyFactory {

    mapping(address => bool) public override isInstance;

    /// @param mapleGlobals_ The address of a Maple Globals contract.
    constructor(address mapleGlobals_) MapleProxyFactory(mapleGlobals_) {}

    function createInstance(bytes calldata arguments_, bytes32 salt_)
        override(IMapleProxyFactory, MapleProxyFactory) public returns (
            address instance_
        )
    {
        isInstance[instance_ = super.createInstance(arguments_, salt_)] = true;
    }

}
