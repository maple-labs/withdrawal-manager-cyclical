// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract MockPool is MockERC20 {

    address public immutable poolDelegate;

    MockERC20       immutable _asset;
    MockPoolManager immutable _manager;

    // TODO: Add functionality for setting the exchange rate to a value other than 1.

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address asset_, address poolDelegate_) MockERC20(name_, symbol_, decimals_) {
        _asset   = MockERC20(asset_);
        _manager = new MockPoolManager(this);

        poolDelegate = poolDelegate_;
    }

    function addLiquidity(uint256 assets_) external {
        _asset.mint(address(this), assets_);
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

    function removeLiquidity(uint256 assets_) external {
        _asset.burn(address(this), assets_);
    }

    function manager() external view returns (address manager_) {
        manager_ = address(_manager);
    }

    function maxRedeem(address account_) external view returns (uint256 maxShares_) {
        uint256 accountAssets = balanceOf[account_];
        uint256 totalAssets   = _asset.balanceOf(address(this));
        maxShares_ = accountAssets > totalAssets ? totalAssets : accountAssets;
    }

}

contract MockPoolManager {

    MockPool _pool;

    constructor(MockPool pool_) {
        _pool = pool_;
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_) {
        assets_ = _pool.redeem(shares_, receiver_, owner_);
    }

}

contract MapleGlobalsMock {

    address public governor;
    address public mapleTreasury;

    bool public protocolPaused;

    uint256 public investorFee;
    uint256 public treasuryFee;

    constructor (address governor_, address mapleTreasury_, uint256 investorFee_, uint256 treasuryFee_) {
        governor      = governor_;
        mapleTreasury = mapleTreasury_;
        investorFee   = investorFee_;
        treasuryFee   = treasuryFee_;
    }

    function setProtocolPaused(bool paused_) external {
        protocolPaused = paused_;
    }

    function setInvestorFee(uint256 investorFee_) external {
        investorFee = investorFee_;
    }

    function setTreasuryFee(uint256 treasuryFee_) external {
        treasuryFee = treasuryFee_;
    }

    function setGovernor(address governor_) external {
        governor = governor_;
    }

    function setMapleTreasury(address mapleTreasury_) external {
        mapleTreasury = mapleTreasury_;
    }

}
