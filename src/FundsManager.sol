// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

contract FundsManager {

    address owner;

    constructor() {
        owner = msg.sender;
    }

    function deployFunds() external {
        // Deposit into AAVE-type protocol
    }

    function claimFunds(address token, address destination, uint256 amount) external {
        require(msg.sender == owner, "FC:CF:NOT_OWNER");
        // Withdraw from AAVE-type protocol
        require(ERC20Helper.transfer(token, destination, amount), "FC:CF:TRANSFER_FAIL");
    }

}