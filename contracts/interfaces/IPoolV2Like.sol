// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IPoolV2Like {

    function balanceOf(address account_) external view returns (uint256 shares_);

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function maxRedeem(address account_) external view returns (uint256 maxShares_);

}
