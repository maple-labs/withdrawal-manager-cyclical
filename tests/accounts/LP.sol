// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";

import { IPoolV2Like }        from "../../contracts/interfaces/IPoolV2Like.sol";
import { IWithdrawalManager } from "../../contracts/interfaces/IWithdrawalManager.sol";

contract LP is ERC20User {

    function pool_deposit(address pool, uint256 assets) external {
        IPoolV2Like(pool).deposit(assets, address(this));
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
