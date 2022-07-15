// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { Address, console, TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }                   from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockPool, MockPoolManager, MapleGlobalsMock } from "./mocks/Mocks.sol";

import { LP }           from "./accounts/LP.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { IWithdrawalManager } from "../contracts/interfaces/IWithdrawalManager.sol";

import { WithdrawalManager }            from "../contracts/WithdrawalManager.sol";
import { WithdrawalManagerFactory }     from "../contracts/WithdrawalManagerFactory.sol";
import { WithdrawalManagerInitializer } from "../contracts/WithdrawalManagerInitializer.sol";

contract WithdrawalManagerTestBase is TestUtils {

    address ADMIN = address(new Address());

    MockERC20          internal _asset;
    MockPool           internal _pool;
    PoolDelegate       internal _poolDelegate;      // TODO This suite is still using accounts. Move to prank
    IWithdrawalManager internal _withdrawalManager;

    uint256 constant COOLDOWN          = 2 weeks;
    uint256 constant DURATION          = 1 weeks;
    uint256 constant START             = 1641164400;  // 1st Monday of 2022
    uint256 constant WITHDRAWAL_WINDOW = 48 hours;

    uint256 constant MAX_ASSETS = 1e36;
    uint256 constant MAX_DELAY  = 52 weeks;
    uint256 constant MAX_SHARES = 1e40;

    function setUp() public virtual {
        MapleGlobalsMock             globals        = new MapleGlobalsMock(address(this), address(0), 0, 0);
        WithdrawalManagerFactory     factory        = new WithdrawalManagerFactory(address(globals));
        WithdrawalManagerInitializer initializer    = new WithdrawalManagerInitializer();
        WithdrawalManager            implementation = new WithdrawalManager();

        factory.registerImplementation(1, address(implementation), address(initializer));
        factory.setDefaultVersion(1);

        _asset        = new MockERC20("MockAsset", "MA", 18);
        _poolDelegate = new PoolDelegate();
        _pool         = new MockPool("MockPool", "MP", 18, address(_asset), address(_poolDelegate));

        _withdrawalManager = IWithdrawalManager(factory.createInstance(
            initializer.encodeArguments(
                address(_asset),
                address(_pool),
                START,
                WITHDRAWAL_WINDOW,
                DURATION
            ),
            "0"
        ));

        // Set admin at pool manager
        MockPoolManager(_pool.manager()).setAdmin(ADMIN);

        // TODO: Increase the exchange rate to more than 1.

        vm.warp(START);
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _initializeLender(uint256 assetsToDeposit_, uint256 minimumAssets_, uint256 maximumAssets_) internal returns (LP lp_, uint256 assets_, uint256 shares_) {
        lp_     = new LP();
        assets_  = constrictToRange(assetsToDeposit_, minimumAssets_, maximumAssets_);
        shares_ = _mintAndDepositAssets(lp_, assets_);
    }

    function _initializeLender(uint256 assetsToDeposit_) internal returns (LP lp_) {
        lp_ = new LP();
        _mintAndDepositAssets(lp_, assetsToDeposit_);
    }

    function _lockShares(LP lp_, uint256 shares_) internal {
        lp_.erc20_approve(address(_pool), address(_withdrawalManager), shares_);
        lp_.withdrawalManager_lockShares(address(_withdrawalManager), shares_);
    }

    function _mintAndDepositAssets(LP lp_, uint256 assets_) internal returns (uint256 shares_) {
        _asset.mint(address(lp_), assets_);

        lp_.erc20_approve(address(_asset), address(_pool), assets_);
        lp_.pool_deposit(address(_pool), assets_);

        shares_ = _pool.balanceOf(address(lp_));
    }

}

contract LockSharesTest is WithdrawalManagerTestBase {

    function test_lockShares_once(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_multipleTimesWithinSamePeriod(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        _lockShares(lp, shares - 1);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_overMultiplePeriods(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        vm.warp(START + DURATION);

        _lockShares(lp, shares - 1);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 3);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        assertEq(_withdrawalManager.totalShares(3),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 1);
    }

}

contract LockSharesFailureTest is WithdrawalManagerTestBase {

    function test_lockShares_failWithZeroAmount() external {
        LP lp = new LP();
        _mintAndDepositAssets(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:ZERO_AMOUNT");
        lp.withdrawalManager_lockShares(address(_withdrawalManager), 0);

        lp.withdrawalManager_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_failWithWithdrawalDue(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        _lockShares(lp, shares - 1);

        vm.warp(START + COOLDOWN);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:WITHDRAW_DUE");
        lp.withdrawalManager_lockShares(address(_withdrawalManager), 1);

        vm.warp(START + COOLDOWN - 1);

        lp.withdrawalManager_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_failWithInsufficientApprove(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares - 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.withdrawalManager_lockShares(address(_withdrawalManager), shares);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.withdrawalManager_lockShares(address(_withdrawalManager), shares);
    }

    function test_lockShares_failWithInsufficientBalance(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares + 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.withdrawalManager_lockShares(address(_withdrawalManager), shares + 1);

        lp.withdrawalManager_lockShares(address(_withdrawalManager), shares);
    }

}

contract UnlockSharesTests is WithdrawalManagerTestBase {

    function test_unlockShares_withinSamePeriod(uint256 assetsToDeposit_, uint256 sharesToUnlock_) external {
        ( LP lp, , uint256 sharesToLock ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);
        sharesToUnlock_ = constrictToRange(sharesToUnlock_, 1, sharesToLock);

        _lockShares(lp, sharesToLock);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        sharesToLock);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        lp.withdrawalManager_unlockShares(address(_withdrawalManager), sharesToUnlock_);

        assertEq(_pool.balanceOf(address(lp)),                 sharesToUnlock_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock - sharesToUnlock_);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), sharesToUnlock_ == sharesToLock ? 0 : 2);

        assertEq(_withdrawalManager.totalShares(2),        sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.pendingWithdrawals(2), sharesToUnlock_ == sharesToLock ? 0 : 1);
    }

    function test_unlockShares_inFollowingPeriod(uint256 assetsToDeposit_, uint256 sharesToUnlock_) external {
        ( LP lp, , uint256 sharesToLock ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);
        sharesToUnlock_ = constrictToRange(sharesToUnlock_, 1, sharesToLock);

        _lockShares(lp, sharesToLock);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        sharesToLock);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        vm.warp(START + DURATION);

        lp.withdrawalManager_unlockShares(address(_withdrawalManager), sharesToUnlock_);

        assertEq(_pool.balanceOf(address(lp)),                 sharesToUnlock_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock - sharesToUnlock_);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), sharesToUnlock_ == sharesToLock ? 0 : 3);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        assertEq(_withdrawalManager.totalShares(3),        sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.pendingWithdrawals(3), sharesToUnlock_ == sharesToLock ? 0 : 1);
    }
}


contract UnlockSharesFailureTests is WithdrawalManagerTestBase {

    function test_unlockShares_failWithZeroAmount() external {
        LP lp = new LP();
        _mintAndDepositAssets(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        lp.withdrawalManager_lockShares(address(_withdrawalManager), 1);


        vm.expectRevert("WM:US:ZERO_AMOUNT");
        lp.withdrawalManager_unlockShares(address(_withdrawalManager), 0);

        lp.withdrawalManager_unlockShares(address(_withdrawalManager), 1);
    }

    function test_unlockShares_failWithWithdrawalDue(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.warp(START + COOLDOWN);

        vm.expectRevert("WM:US:WITHDRAW_DUE");
        lp.withdrawalManager_unlockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN - 1);

        lp.withdrawalManager_unlockShares(address(_withdrawalManager), shares);
    }

    function test_unlockShares_failWithInsufficientBalance(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.expectRevert("WM:US:TRANSFER_FAIL");
        lp.withdrawalManager_unlockShares(address(_withdrawalManager), shares + 1);

        lp.withdrawalManager_unlockShares(address(_withdrawalManager), shares);
    }

}

contract ProcessPeriodTests is WithdrawalManagerTestBase {

    function test_processPeriod_success(uint256 assetsToDeposit_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(_withdrawalManager)),  shares);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        assertEq(_pool.balanceOf(address(_withdrawalManager)),  0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), assets);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    assets);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

}

contract ProcessPeriodFailureTests is WithdrawalManagerTestBase {

    function test_processPeriod_doubleProcess() external {
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        vm.expectRevert("WM:PC:DOUBLE_PROCESS");
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));
    }

}

contract RedeemPositionTests is WithdrawalManagerTestBase {

    function test_redeemPosition_lateWithdraw(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + WITHDRAWAL_WINDOW);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),      0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_lateWithdrawWithRetry(uint256 assetsToDeposit_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + WITHDRAWAL_WINDOW);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertTrue(!_withdrawalManager.isProcessed(4));

        vm.warp(START + 2 * COOLDOWN);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(4),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 0);
        assertTrue(_withdrawalManager.isProcessed(4));
    }

    function test_redeemPosition_fullLiquidity(uint256 assetsToDeposit_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_noLiquidity(uint256 assetsToDeposit_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        // Remove all liquidity.
        _pool.removeLiquidity(assets);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_partialLiquidity(uint256 assetsToDeposit_, uint256 lendedAssets_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);
        lendedAssets_ = constrictToRange(lendedAssets_, 1, assets - 1);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        // Remove the amount of assets that were lended.
        _pool.removeLiquidity(lendedAssets_);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), lendedAssets_);

        // `lendedAssets_` is equivalent to the amount of unredeemed shares due to the 1:1 exchange rate.
        assertEq(_pool.balanceOf(address(lp)),                 lendedAssets_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets - lendedAssets_);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_partialLiquidityWithRetry(uint256 assetsToDeposit_, uint256 lendedAssets_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);
        lendedAssets_ = constrictToRange(lendedAssets_, 1, assets - 1);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        // Remove the amount of assets that were lended.
        _pool.removeLiquidity(lendedAssets_);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), lendedAssets_);

        assertEq(_asset.balanceOf(address(lp)),                 assets - lendedAssets_);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     lendedAssets_);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        lendedAssets_);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertTrue(!_withdrawalManager.isProcessed(4));

        vm.warp(START + 2 * COOLDOWN);

        // The new LP is adding enough additional liquidity for the original LP to exit.
        _mintAndDepositAssets(new LP(), lendedAssets_);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(4),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 0);
        assertTrue(_withdrawalManager.isProcessed(4));
    }

    function test_redeemPosition_withGains() external {
        // TODO: Add example of a withdrawal after the exchange rate increases.
    }

    function test_redeemPosition_withLosses() external {
        // TODO: Add example of a withdrawal after a default occurs.
    }

}

contract RedeemPositionFailureTests is WithdrawalManagerTestBase {

    function test_redeemPosition_noRequest(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        vm.expectRevert("WM:RP:NO_REQUEST");
        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.withdrawalManager_lockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);
    }

    function test_redeemPosition_earlyWithdraw(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.warp(START + COOLDOWN - 1);

        vm.expectRevert("WM:RP:EARLY_WITHDRAW");
        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        vm.warp(START + COOLDOWN);

        lp.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);
    }
}

contract ReclaimAssetsTests is WithdrawalManagerTestBase {

    function test_reclaimAssets_fullLiquidity(uint256 assetsToDeposit_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);
        assertEq(_asset.balanceOf(address(_pool)),              assets);

        assertEq(_withdrawalManager.availableAssets(2), 0);
        assertEq(_withdrawalManager.leftoverShares(2),  0);

        vm.warp(START + COOLDOWN);

        // Process the period explicity, which causes redemption of all shares.
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), assets);
        assertEq(_asset.balanceOf(address(_pool)),              0);

        assertEq(_withdrawalManager.availableAssets(2), assets);
        assertEq(_withdrawalManager.leftoverShares(2),  0);

        vm.warp(START + COOLDOWN + WITHDRAWAL_WINDOW);

        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);

        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);
        assertEq(_asset.balanceOf(address(_pool)),              assets);

        assertEq(_withdrawalManager.availableAssets(2), 0);
        assertEq(_withdrawalManager.leftoverShares(2),  shares);
    }

    function test_reclaimAssets_partialLiquidity(uint256 assetsToDeposit_, uint256 lendedAssets_) external {
        ( LP lp, uint256 assets, uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);
        lendedAssets_ = constrictToRange(lendedAssets_, 1, assets - 1);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);
        assertEq(_asset.balanceOf(address(_pool)),              assets);

        assertEq(_withdrawalManager.availableAssets(2), 0);
        assertEq(_withdrawalManager.leftoverShares(2),  0);

        vm.warp(START + COOLDOWN);

        // Remmove some of the liquidity.
        _pool.removeLiquidity(lendedAssets_);
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        // `lendedAssets_` is equivalent to the amount of unredeemed shares due to the 1:1 exchange rate
        assertEq(_pool.balanceOf(address(_withdrawalManager)), lendedAssets_);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), assets - lendedAssets_);
        assertEq(_asset.balanceOf(address(_pool)),              0);

        assertEq(_withdrawalManager.availableAssets(2), assets - lendedAssets_);
        assertEq(_withdrawalManager.leftoverShares(2),  lendedAssets_);

        vm.warp(START + COOLDOWN + WITHDRAWAL_WINDOW);

        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);

        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);
        assertEq(_asset.balanceOf(address(_pool)),              assets - lendedAssets_);

        assertEq(_withdrawalManager.availableAssets(2), 0);
        assertEq(_withdrawalManager.leftoverShares(2),  shares);
    }

}

contract ReclaimAssetsFailureTests is WithdrawalManagerTestBase {

    function test_reclaimAssets_notPoolDelegate() external {
        LP lp = _initializeLender(1);

        _lockShares(lp, 1);

        vm.warp(START + COOLDOWN);

        // Process the period explicity, which causes redemption of all shares.
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        // Wait until the withdrawal period elapses before reclaiming.
        vm.warp(START + COOLDOWN + DURATION);

        PoolDelegate notPoolDelegate = new PoolDelegate();

        vm.expectRevert("WM:RA:NOT_PD");
        notPoolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);

        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);
    }

    function test_reclaimAssets_earlyReclaim() external {
        LP lp = _initializeLender(1e18);

        _lockShares(lp, 1e18);

        uint256 withdrawalPeriod = _withdrawalManager.withdrawalCycleId(address(lp));
        ( uint256 start_, uint256 end_ ) = _withdrawalManager.getWithdrawalWindowBounds(withdrawalPeriod);

        vm.warp(start_);

        // Process the period explicity, which causes redemption of all shares.
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        vm.warp(end_ - 1);

        vm.expectRevert("WM:RA:EARLY_RECLAIM");
        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), withdrawalPeriod);

        vm.warp(end_);

        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), withdrawalPeriod);
    }

    function test_reclaimAssets_zeroAssets() external {
        LP lp = _initializeLender(1);

        _lockShares(lp, 1);

        vm.warp(START + COOLDOWN + DURATION);

        vm.expectRevert("WM:RA:ZERO_ASSETS");
        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);

        vm.warp(START + COOLDOWN);

        // Process the period explicity, which causes redemption of all shares.
        _poolDelegate.withdrawalManager_processPeriod(address(_withdrawalManager));

        vm.warp(START + COOLDOWN + DURATION);

        _poolDelegate.withdrawalManager_reclaimAssets(address(_withdrawalManager), 2);
    }

}

contract SetNextConfigTests is WithdrawalManagerTestBase {

    function test_setNextConfiguration_failIfNotAdmin() external {
        vm.warp(block.timestamp + 1 days);

        uint256 newDuration_         = 4 weeks;
        uint256 newWithdrawalWindow_ = 1 weeks;

        vm.expectRevert("WM:SNC:NOT_ADMIN");
        _withdrawalManager.setNextConfiguration(newDuration_, newWithdrawalWindow_);
    }

    function test_setNextConfiguration_failIOutOfBOunds() external {
        vm.warp(block.timestamp + 1 days);

        // TODO: Remove appended underscore syntax in all tests
        uint256 newDuration_         = 4 weeks;
        uint256 newWithdrawalWindow_ = 4 weeks + 1 seconds;

        vm.startPrank(ADMIN);
        vm.expectRevert("WM:SNC:OOB");
        _withdrawalManager.setNextConfiguration(newDuration_, newWithdrawalWindow_);
        vm.stopPrank();
    }

    function test_setNextConfiguration() external {
        vm.warp(block.timestamp + 1 days);

        uint256 newDuration_         = 4 weeks;
        uint256 newWithdrawalWindow_ = 1 weeks;

        ( uint64 startingIndex_, uint64 start_, uint64 withdrawalWindow_, uint64 duration_ ) = _withdrawalManager.configurations(0);

        assertEq(startingIndex_,    0);
        assertEq(start_,            START);
        assertEq(duration_,         DURATION);
        assertEq(withdrawalWindow_, WITHDRAWAL_WINDOW);

        vm.prank(ADMIN);
        _withdrawalManager.setNextConfiguration(newDuration_, newWithdrawalWindow_);

        ( startingIndex_, start_, withdrawalWindow_, duration_ ) = _withdrawalManager.configurations(1);

        assertEq(startingIndex_,    3);
        assertEq(start_,            START + (3 * DURATION));  // End + 2 * DURATION
        assertEq(duration_,         newDuration_);
        assertEq(withdrawalWindow_, newWithdrawalWindow_);

        // Assert that some view functions return the current configuration
        assertEq(_withdrawalManager.cycleDuration(), DURATION);

        vm.warp(start_);

        // Assert that some view functions return the current configuration
        assertEq(_withdrawalManager.cycleDuration(), newDuration_);
    }

    function test_setNextConfiguration_doNotAffectExistingWithdrawals() external {
        uint256 assetsToDeposit_     = 1e30;
        uint256 newDuration_         = 4 weeks;
        uint256 newWithdrawalWindow_ = 1 weeks;

        ( LP lp_, , uint256 shares_ ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        vm.warp(block.timestamp + 1 days);

        _lockShares(lp_, shares_);

        ( uint256 lockedShares_, uint256 withdrawalPeriod_ ) = _withdrawalManager.requests(address(lp_));
        ( uint256 start_,        uint256 end_ )              = _withdrawalManager.getWithdrawalWindowBounds(withdrawalPeriod_);

        assertEq(lockedShares_,     shares_);
        assertEq(withdrawalPeriod_, 2);
        assertEq(start_,            START + (2 * DURATION));
        assertEq(end_,              START + (2 * DURATION) + WITHDRAWAL_WINDOW);

        vm.prank(ADMIN);
        _withdrawalManager.setNextConfiguration(newDuration_, newWithdrawalWindow_);

        ( lockedShares_,  withdrawalPeriod_ ) = _withdrawalManager.requests(address(lp_));
        ( start_,         end_ )              = _withdrawalManager.getWithdrawalWindowBounds(withdrawalPeriod_);

        assertEq(lockedShares_,     shares_);
        assertEq(withdrawalPeriod_, 2);
        assertEq(start_,            START + (2 * DURATION));
        assertEq(end_,              START + (2 * DURATION) + WITHDRAWAL_WINDOW);
    }

    function test_setNextConfiguration_overridesNextConfiguration() external {
        vm.warp(block.timestamp + 1 days);

        uint256 newDuration_         = 4 weeks;
        uint256 newWithdrawalWindow_ = 1 weeks;

        ( uint64 startingIndex_, uint64 start_, uint64 withdrawalWindow_, uint64 duration_ ) = _withdrawalManager.configurations(0);

        assertEq(startingIndex_,    0);
        assertEq(start_,            START);
        assertEq(duration_,         DURATION);
        assertEq(withdrawalWindow_, WITHDRAWAL_WINDOW);

        vm.prank(ADMIN);
        _withdrawalManager.setNextConfiguration(newDuration_, newWithdrawalWindow_);

        ( startingIndex_,  start_,  withdrawalWindow_,  duration_ ) = _withdrawalManager.configurations(1);

        assertEq(startingIndex_,    3);
        assertEq(start_,            START + (3 * DURATION));
        assertEq(duration_,         newDuration_);
        assertEq(withdrawalWindow_, newWithdrawalWindow_);

        uint256 updatedDuration_         = 4 days;
        uint256 updatedWithdrawalWindow_ = 1 days;

        // Set Updated values
        vm.prank(ADMIN);
        _withdrawalManager.setNextConfiguration(updatedDuration_, updatedWithdrawalWindow_);

        ( startingIndex_,  start_,  withdrawalWindow_,  duration_ ) = _withdrawalManager.configurations(1);

        assertEq(startingIndex_,    3);
        assertEq(start_,            START + (3 * DURATION));
        assertEq(duration_,         updatedDuration_);
        assertEq(withdrawalWindow_, updatedWithdrawalWindow_);

        // The 2 configuration slot is still empty
        ( startingIndex_,  start_,  withdrawalWindow_,  duration_ ) = _withdrawalManager.configurations(2);

        assertEq(startingIndex_,    0);
        assertEq(start_,            0);
        assertEq(duration_,         0);
        assertEq(withdrawalWindow_, 0);
    }

}

contract MultiUserTests is WithdrawalManagerTestBase {

    function test_multipleWithdrawals_fullLiquidity() external {
        LP lp1 = _initializeLender(2e18);
        LP lp2 = _initializeLender(5e18);
        LP lp3 = _initializeLender(3e18);

        _lockShares(lp1, 2e18);
        _lockShares(lp2, 5e18);
        _lockShares(lp3, 3e18);

        // Warp to the beggining of the withdrawal period.
        vm.warp(START + COOLDOWN);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18 + 5e18 + 3e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // First LP redeems his shares, causing all shares to be redeemed.
        lp1.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 5e18 + 3e18);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 2);
        assertEq(_withdrawalManager.availableAssets(2),    5e18 + 3e18);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Second LP redeems his shares.
        lp2.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                5e18);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 3e18);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    3e18);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Third LP redeems his shares.
        lp3.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                5e18);
        assertEq(_asset.balanceOf(address(lp3)),                3e18);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 0);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    // The end result of this scenario is the same as if zero liquidity is available.
    function test_multipleWithdrawals_noPoolInteraction() external {
        LP lp1 = _initializeLender(2e18);
        LP lp2 = _initializeLender(5e18);
        LP lp3 = _initializeLender(3e18);

        _lockShares(lp1, 2e18);
        _lockShares(lp2, 5e18);
        _lockShares(lp3, 3e18);

        // Withdrawal period elapses, preventing redemption of shares.
        vm.warp(START + COOLDOWN + WITHDRAWAL_WINDOW);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18 + 5e18 + 3e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // First LP reclaims, only receiving back the shares he previously locked.
        lp1.withdrawalManager_redeemPosition(address(_withdrawalManager), 2e18);

        assertEq(_pool.balanceOf(address(lp1)),                2e18);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 5e18 + 3e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 2);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     5e18 + 3e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Second LP reclaims.
        lp2.withdrawalManager_redeemPosition(address(_withdrawalManager), 5e18);

        assertEq(_pool.balanceOf(address(lp1)),                2e18);
        assertEq(_pool.balanceOf(address(lp2)),                5e18);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 3e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     3e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Third LP reclaims.
        lp3.withdrawalManager_redeemPosition(address(_withdrawalManager), 3e18);

        assertEq(_pool.balanceOf(address(lp1)),                2e18);
        assertEq(_pool.balanceOf(address(lp2)),                5e18);
        assertEq(_pool.balanceOf(address(lp3)),                3e18);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 0);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_multipleWithdrawals_partialLiquidity() external {
        LP lp1 = _initializeLender(2e18);
        LP lp2 = _initializeLender(5e18);
        LP lp3 = _initializeLender(3e18);

        _lockShares(lp1, 2e18);
        _lockShares(lp2, 5e18);
        _lockShares(lp3, 3e18);

        // Warp to the beggining of the withdrawal period
        vm.warp(START + COOLDOWN);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18 + 5e18 + 3e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // Remove half of the required assets.
        _pool.removeLiquidity((2e18 + 5e18 + 3e18) / 2);

        // First LP performs a partial redemption, redeeming half of all shares.
        lp1.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1e18 + 2.5e18 + 1.5e18);

        assertEq(_asset.balanceOf(address(lp1)),                1e18);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 2.5e18 + 1.5e18);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 1e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 2);
        assertEq(_withdrawalManager.availableAssets(2),    2.5e18 + 1.5e18);
        assertEq(_withdrawalManager.leftoverShares(2),     2.5e18 + 1.5e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        // The leftover shares are moved to the next withdrawal period (4).
        assertEq(_withdrawalManager.totalShares(4),        1e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));

        // Second LP redeems.
        lp2.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1e18 + 2.5e18 + 1.5e18);

        assertEq(_asset.balanceOf(address(lp1)),                1e18);
        assertEq(_asset.balanceOf(address(lp2)),                2.5e18);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 1.5e18);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 1e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 3e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 2.5e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 4);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    1.5e18);
        assertEq(_withdrawalManager.leftoverShares(2),     1.5e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        1e18 + 2.5e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 2);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));

        // Third LP redeems.
        lp3.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1e18 + 2.5e18 + 1.5e18);

        assertEq(_asset.balanceOf(address(lp1)),                1e18);
        assertEq(_asset.balanceOf(address(lp2)),                2.5e18);
        assertEq(_asset.balanceOf(address(lp3)),                1.5e18);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 1e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 2.5e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 1.5e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 4);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        1e18 + 2.5e18 + 1.5e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 3);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));
    }

    function test_multipleWithdrawals_staggeredWithdrawals() external {
        LP lp1 = _initializeLender(2e18);
        LP lp2 = _initializeLender(8e18);
        LP lp3 = _initializeLender(5e18);

        // PERIOD 0: LP1 locks shares.
        _lockShares(lp1, 2e18);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                8e18);
        assertEq(_pool.balanceOf(address(lp3)),                5e18);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 0);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        2e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // PERIOD 1: LP2 locks shares.
        vm.warp(START + DURATION);

        _lockShares(lp2, 8e18);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                5e18);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18 + 8e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 8e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 0);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        2e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(3),        8e18);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 1);
        assertEq(_withdrawalManager.availableAssets(3),    0);
        assertEq(_withdrawalManager.leftoverShares(3),     0);
        assertTrue(!_withdrawalManager.isProcessed(3));

        // PERIOD 2: LP3 locks shares, LP1 reedems shares.
        vm.warp(START + 2 * DURATION);

        _lockShares(lp3, 5e18);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 2e18 + 8e18 + 5e18);

        assertEq(_asset.balanceOf(address(lp1)),                0);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 2e18);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 8e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 5e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 4);

        assertEq(_withdrawalManager.totalShares(2),        2e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(3),        8e18);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 1);
        assertEq(_withdrawalManager.availableAssets(3),    0);
        assertEq(_withdrawalManager.leftoverShares(3),     0);
        assertTrue(!_withdrawalManager.isProcessed(3));

        assertEq(_withdrawalManager.totalShares(4),        5e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));

        lp1.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 8e18 + 5e18);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                0);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 8e18);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 5e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(3),        8e18);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 1);
        assertEq(_withdrawalManager.availableAssets(3),    0);
        assertEq(_withdrawalManager.leftoverShares(3),     0);
        assertTrue(!_withdrawalManager.isProcessed(3));

        assertEq(_withdrawalManager.totalShares(4),        5e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));

        // PERIOD 3: LP2 redeems shares.
        vm.warp(START + 3 * DURATION);

        lp2.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 5e18);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                8e18);
        assertEq(_asset.balanceOf(address(lp3)),                0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 5e18);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(3),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 0);
        assertEq(_withdrawalManager.availableAssets(3),    0);
        assertEq(_withdrawalManager.leftoverShares(3),     0);
        assertTrue(_withdrawalManager.isProcessed(3));

        assertEq(_withdrawalManager.totalShares(4),        5e18);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(!_withdrawalManager.isProcessed(4));

        // PERIOD 4: LP3 redeems shares.
        vm.warp(START + 4 * DURATION);

        lp3.withdrawalManager_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp1)),                0);
        assertEq(_pool.balanceOf(address(lp2)),                0);
        assertEq(_pool.balanceOf(address(lp3)),                0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp1)),                2e18);
        assertEq(_asset.balanceOf(address(lp2)),                8e18);
        assertEq(_asset.balanceOf(address(lp3)),                5e18);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp1)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp2)), 0);
        assertEq(_withdrawalManager.lockedShares(address(lp3)), 0);

        assertEq(_withdrawalManager.withdrawalCycleId(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalCycleId(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(3),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 0);
        assertEq(_withdrawalManager.availableAssets(3),    0);
        assertEq(_withdrawalManager.leftoverShares(3),     0);
        assertTrue(_withdrawalManager.isProcessed(3));

        assertEq(_withdrawalManager.totalShares(4),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 0);
        assertEq(_withdrawalManager.availableAssets(4),    0);
        assertEq(_withdrawalManager.leftoverShares(4),     0);
        assertTrue(_withdrawalManager.isProcessed(4));
    }

}
