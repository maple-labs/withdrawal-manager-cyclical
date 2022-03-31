// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../../lib/erc20/contracts/test/accounts/ERC20User.sol";

import { IPoolV2 }            from "../../interfaces/IPoolV2.sol";
import { IWithdrawalManager } from "../../interfaces/IWithdrawalManager.sol";

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

    function wm_lockShares(address wm, uint256 shares) external {
        IWithdrawalManager(wm).lockShares(shares);
    }

    function wm_unlockShares(address wm, uint256 shares) external {
        IWithdrawalManager(wm).unlockShares(shares);
    }

    function wm_redeemPosition(address wm, uint256 shares) external {
        IWithdrawalManager(wm).redeemPosition(shares);
    }

}
