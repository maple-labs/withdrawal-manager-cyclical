// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20Helper } from "../../modules/erc20-helper/src/ERC20Helper.sol";

import { ICashManagerLike, IOldPoolV2Like } from "../../contracts/interfaces/Interfaces.sol";

contract FundsRecipient {

    function payInterest(address token, address pool, uint256 amount) external {
        require(ERC20Helper.approve(token, IOldPoolV2Like(pool).cashManager(), amount));
        ICashManagerLike(IOldPoolV2Like(pool).cashManager()).collectInterest(token, amount);
    }

    function payPrincipal(address token, address pool, uint256 amount) external {
        require(ERC20Helper.transfer(token, IOldPoolV2Like(pool).principalManager(), amount));
    }

}
