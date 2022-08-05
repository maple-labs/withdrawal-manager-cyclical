// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract MockGlobals {

    address public governor;

    constructor (address governor_) {
        governor = governor_;
    }

}

contract MockPool is MockERC20 {

    address poolDelegate;

    uint256 sharePrice;

    MockERC20       _asset;
    MockPoolManager _manager;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address asset_, address poolDelegate_) MockERC20(name_, symbol_, decimals_) {
        _asset   = MockERC20(asset_);
        _manager = new MockPoolManager(address(this), poolDelegate_);

        poolDelegate = poolDelegate_;
        sharePrice   = 1;
    }

    function asset() external view returns (address asset_) {
        asset_ = address(_asset);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        shares_ = assets_;
        balanceOf[receiver_] += shares_;
        _asset.transferFrom(msg.sender, address(this), assets_);
    }

    function manager() external view returns (address manager_) {
        manager_ = address(_manager);
    }

    function maxRedeem(address account_) external view returns (uint256 maxShares_) {
        uint256 accountAssets = balanceOf[account_];
        uint256 totalAssets   = _asset.balanceOf(address(this));
        maxShares_ = accountAssets > totalAssets ? totalAssets : accountAssets;
    }

    function previewRedeem(uint256 shares_) external view returns (uint256 assets_) {
        assets_ = sharePrice * shares_;
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_) {
        assets_ = sharePrice * shares_;
        balanceOf[owner_] -= shares_;
        _asset.transfer(receiver_, assets_);
    }

    function __setSharePrice(uint256 sharePrice_) external {
        sharePrice = sharePrice_;
    }

}

contract MockPoolManager {

    address public admin;
    address public pool;

    constructor(address pool_, address admin_) {
        pool = pool_;
        admin = admin_;
    }

}

contract MockWithdrawalManagerMigrator {

    address pool;

    fallback() external {
        pool = abi.decode(msg.data, (address));
    }

}
