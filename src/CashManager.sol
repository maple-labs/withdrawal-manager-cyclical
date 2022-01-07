// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

contract CashManager {

    address public owner;

    uint256 public freeCash;
    uint256 public issuanceInterval;
    uint256 public issuanceRate;
    uint256 public lastUpdated;
    uint256 public totalUnlockedAtEndOfInterval;

    constructor() {
        owner = msg.sender;
        issuanceInterval = 2;
    }

    function deployFunds() external {
        // Deposit into AAVE-type protocol
    }

    function moveFunds(address token, address destination, uint256 amount) external {
        require(msg.sender == owner,          "CM:MF:NOT_OWNER");
        require(amount <= unlockedBalance(),  "CM:MF:INSUF_FUNDS");
        require(destination != address(this), "CM:MF:WRONG_ADDR");

        // Reduce the amount of freeCash by the amount being withdrawn
        freeCash = unlockedBalance() - amount;

        // If issuance is done (interval has passed), set rate to zero
        issuanceRate = block.timestamp >= (lastUpdated + issuanceInterval) ? 0 : issuanceRate;

        // Calculate new total unlocked at the end of the current interval (corresponding to the new rate and freeCash)
        totalUnlockedAtEndOfInterval = getTotalUnlockedAtEndOfInterval();

        require(ERC20Helper.transfer(token, destination, amount), "CM:MF:TRANSFER_FAIL");
    }

    function collectInterest(address token, uint256 amount) external {
        // 1. Determine unlocked cash at this moment using old equation
        freeCash = unlockedBalance();

        // 2. Determine unlocked cash at the end of the interval corresponding to the last deposit (this is just `totalUnlockedAtEndOfInterval`)
        // 3. Determine unlocked cash at the end of the interval of the new deposit (this is just `amount`)
        // 4. Sum 2 and 3
        totalUnlockedAtEndOfInterval = getTotalUnlockedAtEndOfInterval() + amount;

        // 5. Divide 4 by 1 to get issuanceRate of new equation for the new interval
        issuanceRate = (totalUnlockedAtEndOfInterval - freeCash) / issuanceInterval;  // (seconds == days for the time being for simplicity)

        // 6. Update "zero" reference point for time
        lastUpdated = block.timestamp;

        // 7. transferFrom amount
        require(ERC20Helper.transferFrom(token, msg.sender, address(this), amount));
    }

    function collectPrincipal(address token, address sender, uint256 amount) external {
        // Update the free cash to raise the "y-intercept"
        freeCash = unlockedBalance() + amount;

        // If issuance is done (interval has passed), set rate to zero
        issuanceRate = block.timestamp > (lastUpdated + issuanceInterval) ? 0 : issuanceRate;

        // Calculate new total unlocked at the end of the current interval (corresponding to the new rate and freeCash)
        totalUnlockedAtEndOfInterval = getTotalUnlockedAtEndOfInterval();

        require(ERC20Helper.transferFrom(token, sender, address(this), amount), "CM:CP:TRANSFER_FROM");
    }

    function unlockedBalance() public view returns (uint256) {
        uint256 timeSinceUpdate = block.timestamp - lastUpdated;
        uint256 dTime           = timeSinceUpdate > issuanceInterval ? issuanceInterval : timeSinceUpdate;
        return issuanceRate * dTime + freeCash;
    }

    function getTotalUnlockedAtEndOfInterval() internal view returns (uint256) {
        uint256 timeSinceUpdate = block.timestamp - lastUpdated;
        uint256 timeRemaining   = timeSinceUpdate > issuanceInterval ? 0 : issuanceInterval - timeSinceUpdate;
        return issuanceRate * timeRemaining + freeCash;
    }

}