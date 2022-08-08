// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IGlobalsLike {

    function isPoolDeployer(address poolDeployer_) external view returns (bool isPoolDeployer_);

}

interface IERC20Like {

    function balanceOf(address account_) external view returns (uint256 balance_);

}

interface IPoolLike {

    function asset() external view returns (address asset_);

    function manager() external view returns (address manager_);

    function previewRedeem(uint256 shares_) external view returns (uint256 assets_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

}

interface IPoolManagerLike {

    function admin() external view returns (address admin_);

}
