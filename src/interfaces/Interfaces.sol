// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface ICashManagerLike {
    function moveFunds(address token, address destination, uint256 amount) external;
    function collectInterest(address token, uint256 amount) external;
    function collectPrincipal(address token, address sender, uint256 amount) external;
    function deployFunds() external;
    function unlockedBalance() external view returns (uint256);
}


interface IPrincipalManagerLike {
    function registerPrincipal(address token, address cashManager, uint256 amount) external;
    function deployFunds() external;
}

interface IPoolV2Like {
    function cashManager() external view returns (address);
    function principalManager() external view returns (address);
}