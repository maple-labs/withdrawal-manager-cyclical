// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IPoolLike {

    function approve(address spender_, uint256 amount_) external returns (bool success_);

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function balanceOf(address account_) external view returns (uint256 shares_);

    function manager() external view returns (address manager_);

    function maxRedeem(address account_) external view returns (uint256 maxShares_);

    function poolDelegate() external view returns (address poolDelegate_);

}

interface IPoolManagerLike {

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

}
