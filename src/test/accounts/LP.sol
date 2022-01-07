// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../../lib/erc20/src/test/accounts/ERC20User.sol";

import { IPoolV2 } from "../../interfaces/IPoolV2.sol";

contract LP is ERC20User {

    function pool_deposit(address pool, uint256 amount) external {
        IPoolV2(pool).deposit(amount);
    }

    function pool_redeem(address pool, uint256 amount) external {
        IPoolV2(pool).redeem(amount);
    }

    function pool_withdraw(address pool, uint256 amount) external {
        IPoolV2(pool).withdraw(amount);
    }

}