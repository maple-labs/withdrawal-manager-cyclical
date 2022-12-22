// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract MockGlobals {

    address public governor;

    bool internal _isValidScheduledCall;

    bool public protocolPaused;

    mapping(address => bool) public isPoolDeployer;

    constructor (address governor_) {
        governor = governor_;
    }

    function isValidScheduledCall(address, address, bytes32, bytes calldata) external view returns (bool isValid_) {
        isValid_ = _isValidScheduledCall;
    }

    function setValidPoolDeployer(address poolDeployer_, bool isValid_) external {
        isPoolDeployer[poolDeployer_] = isValid_;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external {}

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setProtocolPaused(bool protocolPaused_) external {
        protocolPaused = protocolPaused_;
    }

}

contract MockPool is MockERC20 {

    address public manager;
    address public poolDelegate;

    uint256 public sharePrice;

    MockERC20 _asset;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address asset_,
        address poolDelegate_
    )
        MockERC20(name_, symbol_, decimals_)
    {
        _asset = MockERC20(asset_);

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

    function __setPoolManager(address poolManager_) external {
        manager = poolManager_;
    }

    function __setSharePrice(uint256 sharePrice_) external {
        sharePrice = sharePrice_;
    }

}

contract MockPoolManager {

    address public globals;
    address public pool;
    address public poolDelegate;

    uint256 public totalAssets;
    uint256 public unrealizedLosses;

    constructor(address pool_, address poolDelegate_, address globals_) {
        globals      = globals_;
        pool         = pool_;
        poolDelegate = poolDelegate_;
    }

    function __setTotalAssets(uint256 totalAssets_) external {
        totalAssets = totalAssets_;
    }

    function __setUnrealizedLosses(uint256 unrealizedLosses_) external {
        unrealizedLosses = unrealizedLosses_;
    }

}

contract MockWithdrawalManagerMigrator {

    address public pool;

    fallback() external {
        pool = abi.decode(msg.data, (address));
    }

}

