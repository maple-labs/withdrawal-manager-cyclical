// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract MockPoolV2 is MockERC20 {

    MockERC20 internal immutable _asset;

    // TODO: Add functionality for setting the exchange rate to a value other than 1.

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address asset_) MockERC20(name_, symbol_, decimals_) {
        _asset = MockERC20(asset_);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        shares_ = assets_;
        balanceOf[receiver_] += shares_;
        _asset.transferFrom(msg.sender, address(this), assets_);
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_) {
        assets_ = shares_;
        balanceOf[owner_] -= shares_;
        _asset.transfer(receiver_, assets_);
    }

    function maxRedeem(address account_) external view returns (uint256 maxShares_) {
        uint256 accountAssets = balanceOf[account_];
        uint256 totalAssets   = _asset.balanceOf(address(this));
        maxShares_ = accountAssets > totalAssets ? totalAssets : accountAssets;
    }

    function addLiquidity(uint256 assets_) external {
        _asset.mint(address(this), assets_);
    }

    function removeLiquidity(uint256 assets_) external {
        _asset.burn(address(this), assets_);
    }

}