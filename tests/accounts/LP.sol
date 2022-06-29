// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IPoolLike }          from "../../contracts/interfaces/Interfaces.sol";
import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract LP is ERC20User {

    function pool_deposit(address pool_, uint256 assets_) external returns (uint256 shares_) {
        return IPoolLike(pool_).deposit(assets_, address(this));
    }

    function withdrawalManager_lockShares(address withdrawalManager_, uint256 shares_) external returns (uint256 totalShares_) {
        return IWithdrawalManager(withdrawalManager_).lockShares(shares_);
    }

    function withdrawalManager_redeemPosition(address withdrawalManager_, uint256 shares_) external returns (uint256 withdrawnAssets_, uint256 redeemedShares_, uint256 remainingShares_) {
        return IWithdrawalManager(withdrawalManager_).redeemPosition(shares_);
    }

    function withdrawalManager_unlockShares(address withdrawalManager_, uint256 shares_) external returns (uint256 remainingShares_) {
        return IWithdrawalManager(withdrawalManager_).unlockShares(shares_);
    }

}
