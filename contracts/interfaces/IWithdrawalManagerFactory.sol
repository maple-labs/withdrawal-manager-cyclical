// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IMapleProxyFactory } from "../../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";

/// @title WithdrawalManagerFactory deploys WithdrawalManager instances.
interface IWithdrawalManagerFactory is IMapleProxyFactory {

    /**
     *  @dev    Whether the proxy is an instance deployed by this factory.
     *  @param  proxy_      The address of the proxy contract.
     *  @return isInstance_ Whether the proxy is an instance deployed by this factory.
     */
    function isInstance(address proxy_) external view returns (bool isInstance_);

}
