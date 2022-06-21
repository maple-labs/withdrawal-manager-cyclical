// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IPoolLike }          from "../../contracts/interfaces/Interfaces.sol";
import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract LP is ERC20User {

    function pool_deposit(address pool_, uint256 assets_) external {
        IPoolLike(pool_).deposit(assets_, address(this));
    }

    function wm_lockShares(address wm_, uint256 shares_) external {
        IWithdrawalManager(wm_).lockShares(shares_);
    }

    function wm_redeemPosition(address wm_, uint256 shares_) external {
        IWithdrawalManager(wm_).redeemPosition(shares_);
    }

    function wm_unlockShares(address wm_, uint256 shares_) external {
        IWithdrawalManager(wm_).unlockShares(shares_);
    }

}
