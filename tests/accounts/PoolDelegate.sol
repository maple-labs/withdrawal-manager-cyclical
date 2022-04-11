// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract PoolDelegate is ERC20User {

    function wm_processPeriod(address wm_) external {
        IWithdrawalManager(wm_).processPeriod();
    }

    function wm_reclaimAssets(address wm_, uint256 period_) external {
        IWithdrawalManager(wm_).reclaimAssets(period_);
    }

}
