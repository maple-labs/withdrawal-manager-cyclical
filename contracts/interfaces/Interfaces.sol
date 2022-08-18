// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IMapleGlobalsLike {

    function isPoolDeployer(address poolDeployer_) external view returns (bool isPoolDeployer_);

    function isValidScheduledCall(address caller_, address contract_, bytes32 functionId_, bytes calldata callData_) external view returns (bool isValid_);

    function unscheduleCall(address caller_, bytes32 functionId_, bytes calldata callData_) external;

}

interface IERC20Like {

    function balanceOf(address account_) external view returns (uint256 balance_);

}

interface IPoolLike {

    function asset() external view returns (address asset_);

    function convertToShares(uint256 assets_) external view returns (uint256 shares_);

    function manager() external view returns (address manager_);

    function previewRedeem(uint256 shares_) external view returns (uint256 assets_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function totalSupply() external view returns (uint256 totalSupply_);

    function transfer(address account_, uint256 amount_) external returns (bool success_);

}

interface IPoolManagerLike {

    function admin() external view returns (address admin_);

    function globals() external view returns (address globals_);

    function totalAssets() external view returns (uint256 totalAssets_);

    function unrealizedLosses() external view returns (uint256 unrealizedLosses_);

}
