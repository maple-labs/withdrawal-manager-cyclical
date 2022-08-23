// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { console, Address, TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }                   from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { WithdrawalManager }            from "../contracts/WithdrawalManager.sol";
import { WithdrawalManagerFactory }     from "../contracts/WithdrawalManagerFactory.sol";
import { WithdrawalManagerInitializer } from "../contracts/WithdrawalManagerInitializer.sol";

import { MockGlobals, MockPool, MockPoolManager, MockWithdrawalManagerMigrator } from "./mocks/Mocks.sol";

// TODO: Add test cases with multiple lp's withdrawing within the same window.
// TODO: Add test cases when exchange rate is below one.
// TODO: Add test cases for when configuration is updated before / during / after the withdrawal request / execution.

contract WithdrawalManagerTestBase is TestUtils {

    address admin;
    address governor;
    address implementation;
    address initializer;
    address lp;
    address wm;

    uint256 start;

    MockERC20       asset;
    MockGlobals     globals;
    MockPool        pool;
    MockPoolManager poolManager;

    WithdrawalManagerFactory factory;

    WithdrawalManager withdrawalManager;

    function setUp() public virtual {
        admin          = address(new Address());
        governor       = address(new Address());
        implementation = address(new WithdrawalManager());
        initializer    = address(new WithdrawalManagerInitializer());
        lp             = address(new Address());

        start = 1641164400;

        // Create all mocks.
        globals     = new MockGlobals(address(governor));
        asset       = new MockERC20("Wrapped Ether", "WETH", 18);
        pool        = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), admin);
        poolManager = new MockPoolManager(address(pool), admin, address(globals));

        pool.__setPoolManager(address(poolManager));

        // Create factory and register implementation.
        vm.startPrank(governor);
        factory = new WithdrawalManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.setValidPoolDeployer(address(this), true);
        vm.stopPrank();

        // Warp to the starting time.
        vm.warp(start);

        // Create the withdrawal manager instance.
        withdrawalManager = WithdrawalManager(factory.createInstance({
            arguments_: abi.encode(address(pool), 1 weeks, 2 days),
            salt_:      "SALT"
        }));

        wm = address(withdrawalManager);
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function assertConfig(
        uint256 configurationId,
        uint256 initialCycleId,
        uint256 initialCycleTime,
        uint256 cycleDuration,
        uint256 windowDuration
    )
        internal
    {
        (
            uint64 initialCycleId_,
            uint64 initialCycleTime_,
            uint64 cycleDuration_,
            uint64 windowDuration_
        ) = withdrawalManager.cycleConfigs(configurationId);

        assertEq(initialCycleId_,   initialCycleId);
        assertEq(initialCycleTime_, initialCycleTime);
        assertEq(cycleDuration_,    cycleDuration);
        assertEq(windowDuration_,   windowDuration);
    }

}

contract MigrateTests is WithdrawalManagerTestBase {

    address migrator;

    function setUp() public override {
        super.setUp();

        migrator = address(new MockWithdrawalManagerMigrator());
    }

    function test_migrate_notFactory() external {
        vm.expectRevert("WM:M:NOT_FACTORY");
        withdrawalManager.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(address(factory));
        vm.expectRevert("WM:M:FAILED");
        withdrawalManager.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(withdrawalManager.pool(), address(pool));

        vm.prank(address(factory));
        withdrawalManager.migrate(migrator, abi.encode(address(0)));

        assertEq(withdrawalManager.pool(), address(0));
    }

}

contract SetImplementationTests is WithdrawalManagerTestBase {

    address newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new WithdrawalManager());
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("WM:SI:NOT_FACTORY");
        withdrawalManager.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(withdrawalManager.implementation(), implementation);

        vm.prank(withdrawalManager.factory());
        withdrawalManager.setImplementation(newImplementation);

        assertEq(withdrawalManager.implementation(), newImplementation);
    }

}

contract UpgradeTests is WithdrawalManagerTestBase {

    address migrator;
    address newImplementation;

    function setUp() public override {
        super.setUp();

        migrator          = address(new MockWithdrawalManagerMigrator());
        newImplementation = address(new WithdrawalManager());

        vm.startPrank(governor);
        factory.registerImplementation(2, newImplementation, initializer);
        factory.enableUpgradePath(1, 2, migrator);
        vm.stopPrank();
    }

    function test_upgrade_notAdmin() external {
        vm.expectRevert("WM:U:NOT_ADMIN");
        withdrawalManager.upgrade(2, "");
    }

    function test_upgrade_notScheduled() external {
        vm.prank(admin);
        vm.expectRevert("WM:U:NOT_SCHEDULED");
        withdrawalManager.upgrade(2, "");
    }

    function test_upgrade_upgradeFailed() external {
        MockGlobals(globals).__setIsValidScheduledCall(true);
        vm.prank(admin);
        vm.expectRevert("MPF:UI:FAILED");
        withdrawalManager.upgrade(2, "1");
    }

    function test_upgrade_success() external {
        assertEq(withdrawalManager.implementation(), implementation);

        MockGlobals(globals).__setIsValidScheduledCall(true);
        vm.prank(admin);
        withdrawalManager.upgrade(2, abi.encode(address(0)));

        assertEq(withdrawalManager.implementation(), newImplementation);
    }

}

contract SetExitConfigTests is WithdrawalManagerTestBase {

    function test_setExitConfig_notAdmin() external {
        vm.expectRevert("WM:SEC:NOT_ADMIN");
        withdrawalManager.setExitConfig(1, 1);
    }

    function test_setExitConfig_zeroWindow() external {
        vm.prank(admin);
        vm.expectRevert("WM:SEC:ZERO_WINDOW");
        withdrawalManager.setExitConfig(1, 0);
    }

    function test_setExitConfig_windowOutOfBounds() external {
        vm.prank(admin);
        vm.expectRevert("WM:SEC:WINDOW_OOB");
        withdrawalManager.setExitConfig(1, 2);
    }

    function test_setExitConfig_identicalConfig() external {
        vm.prank(admin);
        vm.expectRevert("WM:SEC:IDENTICAL_CONFIG");
        withdrawalManager.setExitConfig(1 weeks, 2 days);
    }

    function test_setExitConfig_addConfig() external {
        assertEq(withdrawalManager.latestConfigId(), 0);
        assertConfig({
            configurationId:  1,
            initialCycleId:   0,
            initialCycleTime: 0,
            cycleDuration:    0,
            windowDuration:   0
        });

        // Add a new configuration.
        vm.prank(admin);
        withdrawalManager.setExitConfig(1, 1);

        assertEq(withdrawalManager.latestConfigId(), 1);
        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + 3 weeks,
            cycleDuration:    1,
            windowDuration:   1
        });
    }

    function test_setExitConfig_updateConfig() external {
        assertEq(withdrawalManager.latestConfigId(), 0);
        assertConfig({
            configurationId:  1,
            initialCycleId:   0,
            initialCycleTime: 0,
            cycleDuration:    0,
            windowDuration:   0
        });

        // Add a new configuration.
        vm.prank(admin);
        withdrawalManager.setExitConfig(1, 1);

        assertEq(withdrawalManager.latestConfigId(), 1);
        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + 3 weeks,
            cycleDuration:    1,
            windowDuration:   1
        });

        // Wait until just before the configuration takes effect and then update it.
        vm.warp(start + 3 weeks - 1);
        vm.prank(admin);
        withdrawalManager.setExitConfig(2, 1);

        assertEq(withdrawalManager.latestConfigId(), 1);
        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3       + 2,
            initialCycleTime: start + 3 weeks + 2 weeks,
            cycleDuration:    2,
            windowDuration:   1
        });
    }

}

contract AddSharesTests is WithdrawalManagerTestBase {

    address pm;

    function setUp() public override {
        super.setUp();

        pm = address(poolManager);

        // Simulate LP transfer into PM.
        pool.mint(pm, 2);

        vm.prank(pm);
        pool.approve(wm, 2);
    }

    function test_addShares_notPoolManager() external {
        vm.expectRevert("WM:AS:NOT_POOL_MANAGER");
        withdrawalManager.addShares(1, lp);
    }

    function test_addShares_pendingRequest() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks - 1 seconds);
        vm.prank(pm);
        vm.expectRevert("WM:AS:WITHDRAWAL_PENDING");
        withdrawalManager.addShares(1, lp);
    }

    function test_addShares_emptyRequest() external {
        vm.prank(pm);
        vm.expectRevert("WM:AS:NO_OP");
        withdrawalManager.addShares(0, lp);
    }

    function test_addShares_failedTransfer() external {
        vm.prank(pm);
        vm.expectRevert("WM:AS:TRANSFER_FROM_FAIL");
        withdrawalManager.addShares(3, lp);
    }

    function test_addShares_createRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(pm),     2);
        assertEq(pool.balanceOf(wm),     0);
        assertEq(pool.allowance(pm, wm), 2);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);
    }

    function test_addShares_refreshRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(pm),     2);
        assertEq(pool.balanceOf(wm),     0);
        assertEq(pool.allowance(pm, wm), 2);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        withdrawalManager.addShares(0, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 1);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);
    }

    function test_addShares_increaseRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(pm),     2);
        assertEq(pool.balanceOf(wm),     0);
        assertEq(pool.allowance(pm, wm), 2);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 2);

        assertEq(pool.balanceOf(pm),     0);
        assertEq(pool.balanceOf(wm),     2);
        assertEq(pool.allowance(pm, wm), 0);
    }

    function test_addShares_delayedUpdate() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(pm),     2);
        assertEq(pool.balanceOf(wm),     0);
        assertEq(pool.allowance(pm, wm), 2);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);

        vm.warp(start + 3 weeks);
        vm.prank(pm);
        withdrawalManager.addShares(0, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     6);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(6), 1);

        assertEq(pool.balanceOf(pm),     1);
        assertEq(pool.balanceOf(wm),     1);
        assertEq(pool.allowance(pm, wm), 1);
    }

}

contract RemoveSharesTests is WithdrawalManagerTestBase {

    address pm;

    function setUp() public override {
        super.setUp();

        pm = address(poolManager);

        // Simulate LP transfer into PM.
        pool.mint(pm, 2);

        vm.prank(pm);
        pool.approve(wm, 2);
    }

    function test_removeShares_notPoolManager() external {
        vm.expectRevert("WM:RS:NOT_POOL_MANAGER");
        withdrawalManager.removeShares(1, lp);
    }

    function test_removeShares_pendingRequest() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks - 1 seconds);
        vm.prank(pm);
        vm.expectRevert("WM:RS:WITHDRAWAL_PENDING");
        withdrawalManager.removeShares(1, lp);
    }

    function test_removeShares_zeroShares() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        vm.expectRevert("WM:RS:SHARES_OOB");
        withdrawalManager.removeShares(0, lp);
    }

    function test_removeShares_sharesUnderflow() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        vm.expectRevert("WM:RS:SHARES_OOB");
        withdrawalManager.removeShares(2, lp);
    }

    function test_removeShares_failedTransfer() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        pool.burn(address(withdrawalManager), 1);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        vm.expectRevert("WM:RS:TRANSFER_FAIL");
        withdrawalManager.removeShares(1, lp);
    }

    function test_removeShares_decreaseRequest() external {
        vm.prank(pm);
        withdrawalManager.addShares(2, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(wm), 2);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        withdrawalManager.removeShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 1);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 1);
    }

    function test_removeShares_cancelRequest() external {
        vm.prank(pm);
        withdrawalManager.addShares(2, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(wm), 2);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        withdrawalManager.removeShares(2, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(wm), 0);
        assertEq(pool.balanceOf(lp), 2);
    }

    function test_removeShares_delayedUpdate() external {
        vm.prank(pm);
        withdrawalManager.addShares(2, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(wm), 2);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 3 weeks);
        vm.prank(pm);
        withdrawalManager.removeShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     6);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(6), 1);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 1);
    }

}

contract ProcessExitTests is WithdrawalManagerTestBase {

    address pm;

    function setUp() public override {
        super.setUp();

        pm = address(poolManager);

        // Simulate LP transfer into PM.
        pool.mint(pm, 3);

        vm.prank(pm);
        pool.approve(wm, 3);
    }

    function test_processExit_notPoolManager() external {
        vm.expectRevert("WM:PE:NOT_PM");
        withdrawalManager.processExit(lp, 0);
    }

    function test_processExit_requestedSharedGtLocked() external {
        vm.startPrank(pm);
        withdrawalManager.addShares(3, lp);
        vm.expectRevert("WM:PE:INVALID_SHARES");
        withdrawalManager.processExit(lp, 4);
    }

    function test_processExit_requestedSharedLtLocked() external {
        vm.startPrank(pm);
        withdrawalManager.addShares(3, lp);
        vm.expectRevert("WM:PE:INVALID_SHARES");
        withdrawalManager.processExit(lp, 2);
    }

    function test_processExit_noRequest() external {
        vm.prank(pm);
        vm.expectRevert("WM:PR:NO_REQUEST");
        withdrawalManager.processExit(lp, 0);
    }

    function test_processExit_preWindow() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks - 1);
        vm.prank(pm);
        vm.expectRevert("WM:PR:NOT_IN_WINDOW");
        withdrawalManager.processExit(lp, 1);
    }

    function test_processExit_postWindow() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks + 2 days);

        vm.prank(pm);
        vm.expectRevert("WM:PR:NOT_IN_WINDOW");
        withdrawalManager.processExit(lp, 1);
    }

    function test_processExit_lostShares() external {
        asset.mint(address(pool), 2);
        poolManager.__setTotalAssets(2);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        pool.burn(address(withdrawalManager), 1);

        vm.warp(start + 2 weeks);
        vm.prank(pm);
        vm.expectRevert("WM:PE:TRANSFER_FAIL");
        withdrawalManager.processExit(lp, 1);
    }

    function test_processExit_fullWithdrawal_fullLiquidity() external {
        asset.mint(address(pool), 2);
        poolManager.__setTotalAssets(6);

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 2 weeks);
        vm.prank(pm);

        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(lp, 1);

        assertEq(redeemableShares, 1);
        assertEq(resultingAssets,  2);

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(wm), 0);
        assertEq(pool.balanceOf(lp), 1);
    }

    function test_processExit_fullWithdrawal_partialLiquidity() external {
        asset.mint(address(pool), 2);
        poolManager.__setTotalAssets(6);  // 2:1

        vm.prank(pm);
        withdrawalManager.addShares(2, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(wm), 2);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 2 weeks);
        vm.prank(pm);

        // Only can redeem 1 share of 2 at 2:1
        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(lp, 2);

        assertEq(redeemableShares, 1);
        assertEq(resultingAssets,  2);

        assertEq(withdrawalManager.exitCycleId(lp),     4);  // Move forward one cycle.
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 1);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 1);
    }

    function test_processExit_fullWithdrawal_noLiquidity() external {
        poolManager.__setTotalAssets(6);  // 2:1

        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 0);

        vm.warp(start + 2 weeks);
        vm.prank(pm);

        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(lp, 1);

        assertEq(redeemableShares, 0);
        assertEq(resultingAssets,  0);

        assertEq(withdrawalManager.exitCycleId(lp),     4);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 1);

        assertEq(pool.balanceOf(wm), 1);
        assertEq(pool.balanceOf(lp), 0);
    }

}

contract LockedLiquidityTests is WithdrawalManagerTestBase {

    address pm;

    function setUp() public override {
        super.setUp();

        pm = address(poolManager);

        vm.startPrank(pm);
        pool.mint(pm, 1);
        pool.approve(address(withdrawalManager), 1);
        withdrawalManager.addShares(1, lp);
        vm.stopPrank();

        poolManager.__setTotalAssets(1);
    }

    function test_lockedLiquidity_beforeWindow() external {
        vm.warp(start + 2 weeks - 1);
        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

    function test_lockedLiquidity_afterWindow() external {
        vm.warp(start + 2 weeks + 2 days);
        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

    function test_lockedLiquidity_duringWindow() external {
        vm.warp(start + 2 weeks);
        assertEq(withdrawalManager.lockedLiquidity(), 1);

        vm.warp(start + 2 weeks + 2 days - 1);
        assertEq(withdrawalManager.lockedLiquidity(), 1);
    }

    function test_lockedLiquidity_duringWindowWithdrawal() external {
        vm.warp(start + 2 weeks);
        assertEq(withdrawalManager.lockedLiquidity(), 1);

        vm.prank(pm);
        withdrawalManager.processExit(lp, 1);

        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

    function test_lockedLiquidity_unrealizedLosses() external {
        poolManager.__setTotalAssets(2);
        poolManager.__setUnrealizedLosses(1);

        vm.warp(start + 2 weeks);
        assertEq(withdrawalManager.lockedLiquidity(), 1);

        vm.prank(pm);
        withdrawalManager.processExit(lp, 1);

        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

}

contract ProcessExitWithMultipleUsers is WithdrawalManagerTestBase {

    address lp2;
    address lp3;

    function setUp() public override{
        super.setUp();

        lp2 = address(new Address());
        lp3 = address(new Address());

        pool.mint(address(poolManager), 800);

        vm.prank(address(poolManager));
        pool.approve(wm, type(uint256).max);
    }

    function test_partialLiquidity_fullMoveShares() external {
        asset.mint(address(pool), 240);     // 1/10 assets available
        poolManager.__setTotalAssets(2400); // 3:1 exchange rate

        vm.startPrank(address(poolManager));
        withdrawalManager.addShares(100, lp);
        withdrawalManager.addShares(300, lp2);
        withdrawalManager.addShares(400, lp3);
        vm.stopPrank();

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    100);
        assertEq(withdrawalManager.exitCycleId(lp2),    3);
        assertEq(withdrawalManager.lockedShares(lp2),   300);
        assertEq(withdrawalManager.exitCycleId(lp3),    3);
        assertEq(withdrawalManager.lockedShares(lp3),   400);
        assertEq(withdrawalManager.totalCycleShares(3), 800);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(wm),  800);
        assertEq(pool.balanceOf(lp),  0);
        assertEq(pool.balanceOf(lp2), 0);
        assertEq(pool.balanceOf(lp3), 0);

        vm.warp(start + 2 weeks);

        // Process all exits
        vm.startPrank(address(poolManager));
        ( uint256 redeemableShares,  uint256 resultingAssets )  = withdrawalManager.processExit(lp,  100);
        asset.burn(address(pool), resultingAssets);
        pool.burn(address(lp),    redeemableShares);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets);

        ( uint256 redeemableShares2, uint256 resultingAssets2 ) = withdrawalManager.processExit(lp2, 300);
        asset.burn(address(pool), resultingAssets2);
        pool.burn(address(lp2),   redeemableShares2);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets2);

        ( uint256 redeemableShares3, uint256 resultingAssets3 ) = withdrawalManager.processExit(lp3, 400);
        asset.burn(address(pool), resultingAssets3);
        pool.burn(address(lp3),   redeemableShares3);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets3);
        vm.stopPrank();

        assertEq(redeemableShares,  10);
        assertEq(resultingAssets,   30);

        assertEq(redeemableShares2, 30);
        assertEq(resultingAssets2,  90);

        assertEq(redeemableShares3, 40);
        assertEq(resultingAssets3,  120);

        assertEq(withdrawalManager.exitCycleId(lp),  4);
        assertEq(withdrawalManager.lockedShares(lp), 90);

        assertEq(withdrawalManager.exitCycleId(lp2),  4);
        assertEq(withdrawalManager.lockedShares(lp2), 270);

        assertEq(withdrawalManager.exitCycleId(lp3),  4);
        assertEq(withdrawalManager.lockedShares(lp3), 360);

        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 720);

        assertEq(pool.balanceOf(wm),  720);
        assertEq(pool.balanceOf(lp),  0);
        assertEq(pool.balanceOf(lp2), 0);
        assertEq(pool.balanceOf(lp3), 0);
    }



    function test_partialLiquidity_partialMoveShares_partialRemoveShares() external {
        asset.mint(address(pool), 240);     // 1/10 assets available
        poolManager.__setTotalAssets(2400); // 3:1 exchange rate

        vm.startPrank(address(poolManager));
        withdrawalManager.addShares(100, lp);
        withdrawalManager.addShares(300, lp2);
        vm.stopPrank();

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    100);
        assertEq(withdrawalManager.exitCycleId(lp2),    3);
        assertEq(withdrawalManager.lockedShares(lp2),   300);
        assertEq(withdrawalManager.exitCycleId(lp3),    0);
        assertEq(withdrawalManager.lockedShares(lp3),   0);
        assertEq(withdrawalManager.totalCycleShares(3), 400);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(wm),  400);
        assertEq(pool.balanceOf(lp),  0);
        assertEq(pool.balanceOf(lp2), 0);

        vm.warp(start + 2 weeks);

        // Process all exits
        vm.startPrank(address(poolManager));
        ( uint256 redeemableShares,  uint256 resultingAssets )  = withdrawalManager.processExit(lp,  100);
        asset.burn(address(pool), resultingAssets);
        pool.burn(address(lp),    redeemableShares);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets);

        ( uint256 redeemableShares2, uint256 resultingAssets2 ) = withdrawalManager.processExit(lp2, 300);
        asset.burn(address(pool), resultingAssets2);
        pool.burn(address(lp2),   redeemableShares2);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets2);
        vm.stopPrank();

        assertEq(redeemableShares,  20);
        assertEq(resultingAssets,   60);

        assertEq(redeemableShares2, 60);
        assertEq(resultingAssets2,  180);

        assertEq(withdrawalManager.exitCycleId(lp),  4);
        assertEq(withdrawalManager.lockedShares(lp), 80);

        assertEq(withdrawalManager.exitCycleId(lp2),  4);
        assertEq(withdrawalManager.lockedShares(lp2), 240);

        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 320);

        assertEq(pool.balanceOf(wm),  320);
        assertEq(pool.balanceOf(lp),  0);
        assertEq(pool.balanceOf(lp2), 0);
    }

}
