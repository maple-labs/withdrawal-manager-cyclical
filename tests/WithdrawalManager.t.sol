// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LP }             from "./accounts/LP.sol";
import { PoolDelegate }   from "./accounts/PoolDelegate.sol";
import { FundsRecipient } from "./mocks/FundsRecipient.sol";

import { OldPoolV2 }         from "../contracts/OldPoolV2.sol";
import { WithdrawalManager } from "../contracts/WithdrawalManager.sol";

contract WithdrawalManagerTests is TestUtils {

    FundsRecipient    _recipient;
    MockERC20         _asset;
    OldPoolV2         _pool;
    PoolDelegate      _poolDelegate;
    WithdrawalManager _withdrawalManager;

    uint256 constant COOLDOWN  = 2 weeks;
    uint256 constant DURATION  = 48 hours;
    uint256 constant FREQUENCY = 1 weeks;
    uint256 constant START     = 1641164400;  // 1st Monday of 2022

    uint256 constant MAX_ASSETS = 1e36;
    uint256 constant MAX_DELAY  = 52 weeks;
    uint256 constant MAX_SHARES = 1e40;

    function setUp() public {
        _asset             = new MockERC20("MockAsset", "MA", 18);
        _recipient         = new FundsRecipient();
        _poolDelegate      = new PoolDelegate();
        _pool              = new OldPoolV2(address(_asset), address(_poolDelegate));
        _withdrawalManager = new WithdrawalManager(address(_asset), address(_pool), START, DURATION, FREQUENCY, COOLDOWN / FREQUENCY);

        // TODO: Increase the exchange rate to more than 1.

        vm.warp(START);
    }

    // TODO: Replace START/DURATION/COOLDOWN warps with (start, end) tuples.

    /***********************************/
    /*** Lock / Unlock Functionality ***/
    /***********************************/

    function test_lockShares_zeroAmount() external {
        LP lp = new LP();
        _mintAndDepositAssets(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:ZERO_AMOUNT");
        lp.wm_lockShares(address(_withdrawalManager), 0);

        lp.wm_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_withdrawalDue(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        _lockShares(lp, shares - 1);

        vm.warp(START + COOLDOWN);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:WITHDRAW_DUE");
        lp.wm_lockShares(address(_withdrawalManager), 1);

        vm.warp(START + COOLDOWN - 1);

        lp.wm_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_insufficientApprove(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares - 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.wm_lockShares(address(_withdrawalManager), shares);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.wm_lockShares(address(_withdrawalManager), shares);
    }

    function test_lockShares_insufficientBalance(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares + 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.wm_lockShares(address(_withdrawalManager), shares + 1);

        lp.wm_lockShares(address(_withdrawalManager), shares);
    }

    function test_lockShares_once(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_multipleTimesWithinSamePeriod(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        _lockShares(lp, shares - 1);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_overMultiplePeriods(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 2, MAX_ASSETS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        _lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        vm.warp(START + FREQUENCY);

        _lockShares(lp, shares - 1);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 3);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        assertEq(_withdrawalManager.totalShares(3),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(3), 1);
    }

    function test_unlockShares_zeroAmount() external {
        LP lp = new LP();
        _mintAndDepositAssets(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        lp.wm_lockShares(address(_withdrawalManager), 1);

        vm.expectRevert("WM:US:ZERO_AMOUNT");
        lp.wm_unlockShares(address(_withdrawalManager), 0);

        lp.wm_unlockShares(address(_withdrawalManager), 1);
    }

    function test_unlockShares_withdrawalDue(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.warp(START + COOLDOWN);

        vm.expectRevert("WM:US:WITHDRAW_DUE");
        lp.wm_unlockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN - 1);

        lp.wm_unlockShares(address(_withdrawalManager), shares);
    }

    function test_unlockShares_insufficientBalance(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.expectRevert("WM:US:TRANSFER_FAIL");
        lp.wm_unlockShares(address(_withdrawalManager), shares + 1);

        lp.wm_unlockShares(address(_withdrawalManager), shares);
    }

    function test_unlockShares_withinSamePeriod(uint256 assetsToDeposit_, uint256 sharesToUnlock_) external {
        ( LP lp, , uint256 sharesToLock ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);
        sharesToUnlock_ = constrictToRange(sharesToUnlock_, 1, sharesToLock);

        _lockShares(lp, sharesToLock);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        sharesToLock);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        lp.wm_unlockShares(address(_withdrawalManager), sharesToUnlock_);

        assertEq(_pool.balanceOf(address(lp)),                 sharesToUnlock_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock - sharesToUnlock_);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), sharesToUnlock_ == sharesToLock ? 0 : 2);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        sharesToLock);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        vm.warp(START + FREQUENCY);

        lp.wm_unlockShares(address(_withdrawalManager), sharesToUnlock_);

        assertEq(_pool.balanceOf(address(lp)),                 sharesToUnlock_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), sharesToLock - sharesToUnlock_);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), sharesToUnlock_ == sharesToLock ? 0 : 3);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        assertEq(_withdrawalManager.totalShares(3),        sharesToLock - sharesToUnlock_);
        assertEq(_withdrawalManager.pendingWithdrawals(3), sharesToUnlock_ == sharesToLock ? 0 : 1);
    }

    /************************/
    /*** Share Redemption ***/
    /************************/

    function test_processPeriod_doubleProcess() external {
        _poolDelegate.wm_processPeriod(address(_withdrawalManager));

        vm.expectRevert("WM:PP:DOUBLE_PROCESS");
        _poolDelegate.wm_processPeriod(address(_withdrawalManager));
    }

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

        _poolDelegate.wm_processPeriod(address(_withdrawalManager));

        assertEq(_pool.balanceOf(address(_withdrawalManager)),  0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), assets);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    assets);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_noRequest(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        vm.expectRevert("WM:RP:NO_REQUEST");
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.wm_lockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);
    }

    function test_redeemPosition_earlyWithdraw(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        vm.warp(START + COOLDOWN - 1);

        vm.expectRevert("WM:RP:EARLY_WITHDRAW");
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);
    }

    function test_redeemPosition_lateWithdraw(uint256 assetsToDeposit_) external {
        ( LP lp, , uint256 shares ) = _initializeLender(assetsToDeposit_, 1, MAX_ASSETS);

        _lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + DURATION);

        lp.wm_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + DURATION);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertTrue(!_withdrawalManager.isProcessed(4));

        vm.warp(START + 2 * COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_recipient), assets);
        lp.wm_redeemPosition(address(_withdrawalManager), shares);
        
        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 0);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_recipient), lendedAssets_);
        lp.wm_redeemPosition(address(_withdrawalManager), lendedAssets_);

        // `lendedAssets_` is equivalent to the amount of unredeemed shares due to the 1:1 exchange rate.
        assertEq(_pool.balanceOf(address(lp)),                 lendedAssets_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets - lendedAssets_);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_recipient), lendedAssets_);
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), lendedAssets_);

        assertEq(_asset.balanceOf(address(lp)),                 assets - lendedAssets_);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     lendedAssets_);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        lendedAssets_);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertTrue(!_withdrawalManager.isProcessed(4));

        vm.warp(START + 2 * COOLDOWN);

        // The new LP is adding enough additional liquidity for the original LP to exit.
        _mintAndDepositAssets(new LP(), lendedAssets_);
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_asset.balanceOf(address(lp)),                 assets);
        assertEq(_asset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

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

    // TODO: Separate tests into multiple contracts.

    /****************************/
    /*** Multi-user Scenarios ***/
    /****************************/

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // First LP redeems his shares, causing all shares to be redeemed.
        lp1.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 2);
        assertEq(_withdrawalManager.availableAssets(2),    5e18 + 3e18);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Second LP redeems his shares.
        lp2.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    3e18);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Third LP redeems his shares.
        lp3.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 0);

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
        vm.warp(START + COOLDOWN + DURATION);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // First LP reclaims, only receiving back the shares he previously locked.
        lp1.wm_redeemPosition(address(_withdrawalManager), 2e18);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 2);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     5e18 + 3e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Second LP reclaims.
        lp2.wm_redeemPosition(address(_withdrawalManager), 5e18);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     3e18);
        assertTrue(_withdrawalManager.isProcessed(2));

        // Third LP reclaims.
        lp3.wm_redeemPosition(address(_withdrawalManager), 3e18);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

        assertEq(_withdrawalManager.totalShares(2),        2e18 + 5e18 + 3e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 3);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // Pool delegate deploys half of the available assets.
        _poolDelegate.pool_deployFunds(address(_pool), address(_recipient), (2e18 + 5e18 + 3e18) / 2);

        // First LP performs a partial redemption, redeeming half of all shares.
        lp1.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

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
        lp2.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 4);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 2);

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
        lp3.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 4);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 4);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 4);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 0);

        assertEq(_withdrawalManager.totalShares(2),        2e18);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableAssets(2),    0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        // PERIOD 1: LP2 locks shares.
        vm.warp(START + FREQUENCY);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 0);

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
        vm.warp(START + 2 * FREQUENCY);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 2);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 4);

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

        lp1.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 3);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 4);

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
        vm.warp(START + 3 * FREQUENCY);

        lp2.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 4);

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
        vm.warp(START + 4 * FREQUENCY);

        lp3.wm_redeemPosition(address(_withdrawalManager), 0);

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

        assertEq(_withdrawalManager.withdrawalPeriod(address(lp1)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp2)), 0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp3)), 0);

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
        lp_.wm_lockShares(address(_withdrawalManager), shares_);
    }

    function _mintAndDepositAssets(LP lp_, uint256 assets_) internal returns (uint256 shares_) {
        _asset.mint(address(lp_), assets_);

        lp_.erc20_approve(address(_asset), _pool.cashManager(), assets_);
        lp_.pool_deposit(address(_pool), assets_);

        shares_ = _pool.balanceOf(address(lp_));
    }

    function _receiveInterest(FundsRecipient recipient_, uint256 assets_) internal {
        _asset.mint(address(recipient_), assets_);
        _recipient.payInterest(address(_asset), address(_pool), assets_);
    }

    function _sufferDefault(uint256 assets) internal {
        // TODO: Implement defaults.
    }

}
