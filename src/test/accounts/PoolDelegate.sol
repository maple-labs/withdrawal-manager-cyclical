// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../../lib/erc20/src/test/accounts/ERC20User.sol";

import { IPoolV2 } from "../../interfaces/IPoolV2.sol";

contract PoolDelegate is ERC20User {

    function pool_claimInterest(address pool) external {
        IPoolV2(pool).claimInterest();
    }

    function pool_deployFunds(address pool, address recipient, uint256 amount) external {
        IPoolV2(pool).deployFunds(recipient, amount);
    }



}