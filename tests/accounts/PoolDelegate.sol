// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract PoolDelegate is ERC20User {

    function withdrawalManager_processPeriod(address withdrawalManager_) external {
        IWithdrawalManager(withdrawalManager_).processPeriod();
    }

    function withdrawalManager_reclaimAssets(address withdrawalManager_, uint256 period_) external returns (uint256 reclaimedAssets_) {
        return IWithdrawalManager(withdrawalManager_).reclaimAssets(period_);
    }

}
