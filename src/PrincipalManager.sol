// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

import { ICashManagerLike } from "./interfaces/Interfaces.sol";

contract PrincipalManager {

    address owner;

    constructor() {
        owner = msg.sender;
    }

    function deployFunds() external {
        // Deposit into AAVE-type protocol
    }

    function registerPrincipal(address token, address cashManager, uint256 amount) external {
        require(msg.sender == owner, "FC:CF:NOT_OWNER");
        // Withdraw from AAVE-type protocol
        require(ERC20Helper.approve(token, cashManager, amount), "FC:CF:APPROVE_FAIL");
        ICashManagerLike(cashManager).collectPrincipal(token, address(this), amount);
    }

}