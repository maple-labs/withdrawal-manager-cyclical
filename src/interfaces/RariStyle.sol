// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IPoolV2 {

    function fundsAsset() external view returns (address);
    function poolDelegate() external view returns (address);
    function cashManager() external view returns (address);
    function interestManager() external view returns (address);
    function principalManager() external view returns (address);
    function principalOut() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 fundsAssetAmount) external;
    function redeem(uint256 poolTokenAmount) external;
    function deployFunds(address recipient, uint256 amount) external;
    function claimInterest() external;
    function claimPrincipal() external;
    function claim() external;
    function exchangeRate() external view returns (uint256);
    function totalHoldings() external view returns (uint256);
    function balanceOfUnderlying(address account) external view returns (uint256);

}
