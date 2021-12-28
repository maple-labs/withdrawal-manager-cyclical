// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IFundsManagerLike {
    function claimFunds(address token, address destination, uint256 amount) external;
    function deployFunds() external;
}

interface IPoolV2Like {
    function cashManager() external view returns (address);
    function principalManager() external view returns (address);
}