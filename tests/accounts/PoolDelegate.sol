// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IOldPoolV2 } from "../../contracts/interfaces/IOldPoolV2.sol";

import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract PoolDelegate is ERC20User {

    function pool_claimInterest(address pool) external {
        IOldPoolV2(pool).claimInterest();
    }

    function pool_deployFunds(address pool, address recipient, uint256 amount) external {
        IOldPoolV2(pool).deployFunds(recipient, amount);
    }

    function wm_processPeriod(address wm) external {
        IWithdrawalManager(wm).processPeriod();
    }

}
