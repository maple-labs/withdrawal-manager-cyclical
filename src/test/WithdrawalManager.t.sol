// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { LP }             from "./accounts/LP.sol";
import { PoolDelegate }   from "./accounts/PoolDelegate.sol";
import { FundsRecipient } from "./mocks/FundsRecipient.sol";

import { PoolV2 }            from "../PoolV2.sol";
import { WithdrawalManager } from "../WithdrawalManager.sol";

contract WithdrawalManagerTests is TestUtils {

    MockERC20         _fundsAsset;
    FundsRecipient    _fundsRecipient;
    PoolV2            _pool;
    PoolDelegate      _poolDelegate;
    WithdrawalManager _withdrawalManager;

    uint256 constant COOLDOWN  = 2 weeks;
    uint256 constant DURATION  = 48 hours;
    uint256 constant FREQUENCY = 1 weeks;
    uint256 constant START     = 1641164400;  // 1st Monday of 2022

    uint256 constant MAX_FUNDS  = 1e36;
    uint256 constant MAX_DELAY  = 52 weeks;
    uint256 constant MAX_SHARES = 1e40;

    function setUp() public {
        _fundsAsset        = new MockERC20("FundsAsset", "FA", 18);
        _poolDelegate      = new PoolDelegate();
        _fundsRecipient    = new FundsRecipient();
        _pool              = new PoolV2(address(_fundsAsset), address(_poolDelegate));
        _withdrawalManager = new WithdrawalManager(address(_pool), address(_fundsAsset), START, DURATION, FREQUENCY, COOLDOWN / FREQUENCY);

        // TODO: Increase the exchange rate to more than 1.

        vm.warp(START);
    }

    // TODO: Replace START/DURATION/COOLDOWN warps with (start, end) tuples.

    /***********************************/
    /*** Lock / Unlock Functionality ***/
    /***********************************/

    function test_lockShares_zeroAmount() external {
        LP lp = new LP();
        mintAndDepositFunds(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:ZERO_AMOUNT");
        lp.wm_lockShares(address(_withdrawalManager), 0);

        lp.wm_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_withdrawalDue(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 2, MAX_FUNDS);

        lockShares(lp, shares - 1);

        vm.warp(START + COOLDOWN);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        vm.expectRevert("WM:LS:WITHDRAW_DUE");
        lp.wm_lockShares(address(_withdrawalManager), 1);

        vm.warp(START + COOLDOWN - 1);

        lp.wm_lockShares(address(_withdrawalManager), 1);
    }

    function test_lockShares_insufficientApprove(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares - 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.wm_lockShares(address(_withdrawalManager), shares);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.wm_lockShares(address(_withdrawalManager), shares);
    }

    function test_lockShares_insufficientBalance(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares + 1);
        vm.expectRevert("WM:LS:TRANSFER_FAIL");
        lp.wm_lockShares(address(_withdrawalManager), shares + 1);

        lp.wm_lockShares(address(_withdrawalManager), shares);
    }

    function test_lockShares_once(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_multipleTimesWithinSamePeriod(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 2, MAX_FUNDS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        lockShares(lp, shares - 1);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
    }

    function test_lockShares_overMultiplePeriods(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 2, MAX_FUNDS);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);

        lockShares(lp, 1);

        assertEq(_pool.balanceOf(address(lp)),                 shares - 1);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 1);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     1);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        1);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);

        vm.warp(START + FREQUENCY);

        lockShares(lp, shares - 1);

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
        mintAndDepositFunds(lp, 1);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), 1);
        lp.wm_lockShares(address(_withdrawalManager), 1);

        vm.expectRevert("WM:US:ZERO_AMOUNT");
        lp.wm_unlockShares(address(_withdrawalManager), 0);

        lp.wm_unlockShares(address(_withdrawalManager), 1);
    }

    function test_unlockShares_withdrawalDue(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        vm.warp(START + COOLDOWN);

        vm.expectRevert("WM:US:WITHDRAW_DUE");
        lp.wm_unlockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN - 1);

        lp.wm_unlockShares(address(_withdrawalManager), shares);
    }

    function test_unlockShares_insufficientBalance(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        vm.expectRevert("WM:US:TRANSFER_FAIL");
        lp.wm_unlockShares(address(_withdrawalManager), shares + 1);

        lp.wm_unlockShares(address(_withdrawalManager), shares);
    }

    function test_unlockShares_withinSamePeriod(uint256 fundsToDeposit_, uint256 sharesToUnlock_) external {
        ( LP lp, , uint256 sharesToLock ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);
        sharesToUnlock_ = constrictToRange(sharesToUnlock_, 1, sharesToLock);

        lockShares(lp, sharesToLock);

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

    function test_unlockShares_inFollowingPeriod(uint256 fundsToDeposit_, uint256 sharesToUnlock_) external {
        ( LP lp, , uint256 sharesToLock ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);
        sharesToUnlock_ = constrictToRange(sharesToUnlock_, 1, sharesToLock);

        lockShares(lp, sharesToLock);

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

    function test_processPeriod_success(uint256 fundsToDeposit_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(_withdrawalManager)),       shares);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableFunds(2),     0);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.wm_processPeriod(address(_withdrawalManager));

        assertEq(_pool.balanceOf(address(_withdrawalManager)),       0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), funds);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertEq(_withdrawalManager.availableFunds(2),     funds);
        assertEq(_withdrawalManager.leftoverShares(2),     0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_noRequest(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        vm.expectRevert("WM:RP:NO_REQUEST");
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        lp.erc20_approve(address(_pool), address(_withdrawalManager), shares);
        lp.wm_lockShares(address(_withdrawalManager), shares);

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);
    }

    function test_redeemPosition_earlyWithdraw(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        vm.warp(START + COOLDOWN - 1);

        vm.expectRevert("WM:RP:EARLY_WITHDRAW");
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);
    }

    function test_redeemPosition_lateWithdraw(uint256 fundsToDeposit_) external {
        ( LP lp, , uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + DURATION);

        lp.wm_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_lateWithdrawWithRetry(uint256 fundsToDeposit_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN + DURATION);

        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

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

        assertEq(_fundsAsset.balanceOf(address(lp)),                 funds);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(4),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 0);
        assertTrue(_withdrawalManager.isProcessed(4));
    }

    function test_redeemPosition_fullLiquidity(uint256 fundsToDeposit_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        lp.wm_redeemPosition(address(_withdrawalManager), shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 funds);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_noLiquidity(uint256 fundsToDeposit_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 1, MAX_FUNDS);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_fundsRecipient), funds);
        lp.wm_redeemPosition(address(_withdrawalManager), shares);
        
        assertEq(_pool.balanceOf(address(lp)),                 shares);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_partialLiquidity(uint256 fundsToDeposit_, uint256 lendedFunds_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 2, MAX_FUNDS);
        lendedFunds_ = constrictToRange(lendedFunds_, 1, funds - 1);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_fundsRecipient), lendedFunds_);
        lp.wm_redeemPosition(address(_withdrawalManager), lendedFunds_);

        // `lendedFunds_` is equivalent to the amount of unredeemed shares due to the 1:1 exchange rate.
        assertEq(_pool.balanceOf(address(lp)),                 lendedFunds_);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 funds - lendedFunds_);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     0);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 0);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));
    }

    function test_redeemPosition_partialLiquidityWithRetry(uint256 fundsToDeposit_, uint256 lendedFunds_) external {
        ( LP lp, uint256 funds, uint256 shares ) = initializeLender(fundsToDeposit_, 2, MAX_FUNDS);
        lendedFunds_ = constrictToRange(lendedFunds_, 1, funds - 1);

        lockShares(lp, shares);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), shares);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 0);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     shares);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 2);

        assertEq(_withdrawalManager.totalShares(2),        shares);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 1);
        assertTrue(!_withdrawalManager.isProcessed(2));

        vm.warp(START + COOLDOWN);

        _poolDelegate.pool_deployFunds(address(_pool), address(_fundsRecipient), lendedFunds_);
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), lendedFunds_);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 funds - lendedFunds_);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_withdrawalManager.lockedShares(address(lp)),     lendedFunds_);
        assertEq(_withdrawalManager.withdrawalPeriod(address(lp)), 4);

        assertEq(_withdrawalManager.totalShares(2),        0);
        assertEq(_withdrawalManager.pendingWithdrawals(2), 0);
        assertTrue(_withdrawalManager.isProcessed(2));

        assertEq(_withdrawalManager.totalShares(4),        lendedFunds_);
        assertEq(_withdrawalManager.pendingWithdrawals(4), 1);
        assertTrue(!_withdrawalManager.isProcessed(4));

        vm.warp(START + 2 * COOLDOWN);

        // The new LP is adding enough additional liquidity for the original LP to exit.
        mintAndDepositFunds(new LP(), lendedFunds_);
        lp.wm_redeemPosition(address(_withdrawalManager), 0);

        assertEq(_pool.balanceOf(address(lp)),                 0);
        assertEq(_pool.balanceOf(address(_withdrawalManager)), 0);

        assertEq(_fundsAsset.balanceOf(address(lp)),                 funds);
        assertEq(_fundsAsset.balanceOf(address(_withdrawalManager)), 0);

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

    /****************************/
    /*** Multi-User Scenarios ***/
    /****************************/

    // TODO: Include in separate PR.

    /***********************/
    /*** Invariant Tests ***/
    /***********************/

    // TODO: Include in separate PR.

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function initializeLender(uint256 fundsToDeposit_, uint256 minimumFunds_, uint256 maximumFunds_) internal returns (LP lp_, uint256 funds_, uint256 shares_) {
        lp_     = new LP();
        funds_  = constrictToRange(fundsToDeposit_, minimumFunds_, maximumFunds_);
        shares_ = mintAndDepositFunds(lp_, funds_);
    }

    function lockShares(LP lp_, uint256 shares_) internal {
        lp_.erc20_approve(address(_pool), address(_withdrawalManager), shares_);
        lp_.wm_lockShares(address(_withdrawalManager), shares_);
    }

    function mintAndDepositFunds(LP lp_, uint256 funds_) internal returns (uint256 shares_) {
        _fundsAsset.mint(address(lp_), funds_);

        lp_.erc20_approve(address(_fundsAsset), _pool.cashManager(), funds_);
        lp_.pool_deposit(address(_pool), funds_);

        shares_ = _pool.balanceOf(address(lp_));
    }

    function receiveInterest(FundsRecipient fundsRecipient_, uint256 funds_) internal {
        _fundsAsset.mint(address(fundsRecipient_), funds_);
        _fundsRecipient.payInterest(address(_fundsAsset), address(_pool), funds_);
    }

    function sufferDefault(uint256 funds) internal {
        // TODO: Implement defaults.
    }

}
