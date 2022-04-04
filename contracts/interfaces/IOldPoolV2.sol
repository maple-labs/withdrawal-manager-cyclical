// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IERC20 } from "../../modules/erc20/contracts/interfaces/IERC20.sol";

interface IOldPoolV2 is IERC20 {

    function fundsAsset() external view returns (address);
    function poolDelegate() external view returns (address);
    function cashManager() external view returns (address);
    function interestManager() external view returns (address);
    function principalManager() external view returns (address);
    function principalOut() external view returns (uint256);
    function deposit(uint256 amount) external returns(uint256);
    function withdraw(uint256 fundsAssetAmount) external returns (uint256);
    function redeem(uint256 poolTokenAmount) external returns (uint256);
    function deployFunds(address recipient, uint256 amount) external;
    function claimInterest() external;
    function claimPrincipal() external;
    function claim() external;
    function exchangeRate() external view returns (uint256);
    function totalHoldings() external view returns (uint256);
    function balanceOfUnderlying(address account) external view returns (uint256);
    function previewWithdraw(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewRedeem(uint256 shareAmount) external view returns (uint256 underlyingAmount);

}
