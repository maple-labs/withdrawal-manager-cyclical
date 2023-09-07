// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test }      from "../modules/forge-std/src/Test.sol";
import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MapleWithdrawalManager }            from "../contracts/MapleWithdrawalManager.sol";
import { MapleWithdrawalManagerFactory }     from "../contracts/MapleWithdrawalManagerFactory.sol";
import { MapleWithdrawalManagerInitializer } from "../contracts/MapleWithdrawalManagerInitializer.sol";

import { MockGlobals, MockPool, MockPoolManager, MockWithdrawalManagerMigrator } from "./mocks/Mocks.sol";

contract TestBase is Test {

    address internal governor;
    address internal implementation;
    address internal initializer;
    address internal lp;
    address internal poolDelegate;
    address internal wm;

    uint256 internal start;

    MockERC20       internal asset;
    MockGlobals     internal globals;
    MockPool        internal pool;
    MockPoolManager internal poolManager;

    MapleWithdrawalManager internal withdrawalManager;

    MapleWithdrawalManagerFactory internal factory;

    function setUp() public virtual {
        governor     = makeAddr("governor");
        lp           = makeAddr("lp");
        poolDelegate = makeAddr("poolDelegate");

        implementation = address(new MapleWithdrawalManager());
        initializer    = address(new MapleWithdrawalManagerInitializer());

        start = 1641164400;

        // Create all mocks.
        asset       = new MockERC20("Wrapped Ether", "WETH", 18);
        globals     = new MockGlobals(address(governor));
        pool        = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), poolDelegate);
        poolManager = new MockPoolManager(address(pool), poolDelegate, address(globals));

        pool.__setPoolManager(address(poolManager));

        // Create factory and register implementation.
        vm.startPrank(governor);
        factory = new MapleWithdrawalManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.setValidPoolDeployer(address(this), true);
        vm.stopPrank();

        // Warp to the starting time.
        vm.warp(start);

        // Create the withdrawal manager instance.
        withdrawalManager = MapleWithdrawalManager(factory.createInstance({
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

contract MigrateTests is TestBase {

    address internal migrator;

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

contract SetImplementationTests is TestBase {

    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new MapleWithdrawalManager());
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

contract UpgradeTests is TestBase {

    address internal migrator;
    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        migrator          = address(new MockWithdrawalManagerMigrator());
        newImplementation = address(new MapleWithdrawalManager());

        vm.startPrank(governor);
        factory.registerImplementation(2, newImplementation, initializer);
        factory.enableUpgradePath(1, 2, migrator);
        vm.stopPrank();
    }

    function test_upgrade_notGovernor() external {
        vm.expectRevert("WM:U:NOT_AUTHORIZED");
        withdrawalManager.upgrade(2, "");

        vm.prank(governor);
        withdrawalManager.upgrade(2, abi.encode(address(0)));
    }

    function test_upgrade_notPoolDelegate() external {
        vm.expectRevert("WM:U:NOT_AUTHORIZED");
        withdrawalManager.upgrade(2, "");

        MockGlobals(globals).__setIsValidScheduledCall(true);
        vm.prank(poolDelegate);
        withdrawalManager.upgrade(2, abi.encode(address(0)));
    }

    function test_upgrade_notScheduled() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, "");
    }

    function test_upgrade_upgradeFailed() external {
        MockGlobals(globals).__setIsValidScheduledCall(true);
        vm.prank(poolDelegate);
        vm.expectRevert("MPF:UI:FAILED");
        withdrawalManager.upgrade(2, "1");
    }

    function test_upgrade_success() external {
        assertEq(withdrawalManager.implementation(), implementation);

        MockGlobals(globals).__setIsValidScheduledCall(true);
        vm.prank(poolDelegate);
        withdrawalManager.upgrade(2, abi.encode(address(0)));

        assertEq(withdrawalManager.implementation(), newImplementation);
    }

}

contract SetExitConfigTests is TestBase {

    function test_setExitConfig_failWhenPaused() external {
        globals.__setProtocolPaused(true);

        vm.prank(poolDelegate);
        vm.expectRevert("WM:PROTOCOL_PAUSED");
        withdrawalManager.setExitConfig(1, 1);

        globals.__setProtocolPaused(false);

        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(1, 1);
    }

    function test_setExitConfig_governor() external {
        // Governor should not be allowed.
        vm.prank(governor);
        vm.expectRevert("WM:SEC:NOT_AUTHORIZED");
        withdrawalManager.setExitConfig(1, 1);

        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(1, 1);
    }

    function test_setExitConfig_notPoolDelegate() external {
        vm.expectRevert("WM:SEC:NOT_AUTHORIZED");
        withdrawalManager.setExitConfig(1, 1);

        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(1, 1);
    }

    function test_setExitConfig_zeroWindow() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:SEC:ZERO_WINDOW");
        withdrawalManager.setExitConfig(1, 0);
    }

    function test_setExitConfig_windowOutOfBounds() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:SEC:WINDOW_OOB");
        withdrawalManager.setExitConfig(1, 2);
    }

    function test_setExitConfig_cycleDurationCastOob() external {
        vm.startPrank(poolDelegate);
        vm.expectRevert("WM:UINT64_CAST_OOB");
        withdrawalManager.setExitConfig(uint256(type(uint64).max) + 1, 2 days);

        withdrawalManager.setExitConfig(type(uint64).max, 2 days);
    }

    // NOTE: test_setExitConfig_windowDurationCastOob is not reachable because
    //       withdrawalManager.setExitConfig(uint256(type(uint64).max), uint256(type(uint64).max) + 1); causes "WM:SEC:WINDOW_OOB"

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
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(1 weeks, 1 days);

        assertEq(withdrawalManager.latestConfigId(), 1);
        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + 3 weeks,
            cycleDuration:    1 weeks,
            windowDuration:   1 days
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
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(2 weeks, 2 days);

        assertEq(withdrawalManager.latestConfigId(), 1);

        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + (1 weeks * 3),
            cycleDuration:    2 weeks,
            windowDuration:   2 days
        });

        assertConfig({
            configurationId:  2,
            initialCycleId:   0,
            initialCycleTime: 0,
            cycleDuration:    0,
            windowDuration:   0
        });

        // Wait until a new cycle begins.
        vm.warp(start + 1 weeks);
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(3 weeks, 3 days);

        assertEq(withdrawalManager.latestConfigId(), 2);

        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + (1 weeks * 3),
            cycleDuration:    2 weeks,
            windowDuration:   2 days
        });

        assertConfig({
            configurationId:  2,
            initialCycleId:   1     + 3             + 1,
            initialCycleTime: start + (1 weeks * 3) + 2 weeks,  // 3 weeks for cycles 1-3 + 2 weeks for cycle 4
            cycleDuration:    3 weeks,
            windowDuration:   3 days
        });

        // Update the configuration again within the same cycle in order to overwrite it.
        vm.warp(start + 2 weeks - 1);
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(3 weeks, 1 days);

        assertEq(withdrawalManager.latestConfigId(), 2);

        assertConfig({
            configurationId:  1,
            initialCycleId:   1     + 3,
            initialCycleTime: start + (1 weeks * 3),
            cycleDuration:    2 weeks,
            windowDuration:   2 days
        });

        assertConfig({
            configurationId:  2,
            initialCycleId:   1     + 3             + 1,
            initialCycleTime: start + (1 weeks * 3) + 2 weeks,
            cycleDuration:    3 weeks,
            windowDuration:   1 days
        });
    }

    function test_setExitConfig_complexScenario() external {
        assertEq(withdrawalManager.latestConfigId(), 0);

        assertConfig({
            configurationId:  1,
            initialCycleId:   0,
            initialCycleTime: 0,
            cycleDuration:    0,
            windowDuration:   0
        });

        // 1 full cycles goes by - Current cycle is 2.
        vm.warp(start + 1 weeks + 1);

        // Add a new configuration.
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(2 weeks, 5 days);

        assertEq(withdrawalManager.latestConfigId(), 1);

        assertConfig({
            configurationId:  1,
            initialCycleId:   2     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3),  // Starting at cycle 2 + 3 cycles
            cycleDuration:    2 weeks,
            windowDuration:   5 days
        });

        // In the same cycle, change the config
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(4 weeks, 1 days);

        assertEq(withdrawalManager.latestConfigId(), 1);

        // Still schedule to start the same time as before, but with different configurations, meaning the config was updated.
        assertConfig({
            configurationId:  1,
            initialCycleId:   2     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3),  // Starting at cycle 2 + 3 cycles
            cycleDuration:    4 weeks,
            windowDuration:   1 days
        });

        // Another cycle goes by - current cycle is 3.
        vm.warp(start + 2 weeks);

        // Add a new configuration.
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(3 weeks, 1 days);

        assertEq(withdrawalManager.latestConfigId(), 2);

        // The previous config is still schedule to start at the correct time.
        assertConfig({
            configurationId:  1,
            initialCycleId:   2     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3),  // Starting at cycle 2 + 3 cycles
            cycleDuration:    4 weeks,
            windowDuration:   1 days
        });

        assertConfig({
            configurationId:  2,
            initialCycleId:   3     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3) + 4 weeks,  // Starting at cycle 3 + 3 cycles (2 at config 0 one at config 1)
            cycleDuration:    3 weeks,
            windowDuration:   1 days
        });

        // Warp another cycle - Making the current one 4
        vm.warp(start + 3 weeks);

        // Add yet another config
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(4 weeks, 4 days);

        assertEq(withdrawalManager.latestConfigId(), 3);

        assertConfig({
            configurationId:  3,
            initialCycleId:   4     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3) + 4 weeks + 3 weeks,  // Starting at cycle 4 + 3 cycles (1 at config 0, 1 at config 1, one at config 2)
            cycleDuration:    4 weeks,
            windowDuration:   4 days
        });

        // Update the latest config
        vm.prank(poolDelegate);
        withdrawalManager.setExitConfig(2 weeks, 2 days);

        assertEq(withdrawalManager.latestConfigId(), 3);

        assertConfig({
            configurationId:  3,
            initialCycleId:   4     + 3,
            initialCycleTime: start + 1 weeks + (1 weeks * 3) + 4 weeks + 3 weeks,  // Starting at cycle 4 + 3 cycles (1 at config 0, 1 at config 1, one at config 2)
            cycleDuration:    2 weeks,
            windowDuration:   2 days
        });
    }

}

contract AddSharesTests is TestBase {

    address internal pm;

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

contract RemoveSharesTests is TestBase {

    address internal pm;

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

contract ProcessExitTests is TestBase {

    address internal pm;

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
        withdrawalManager.processExit(0, lp);
    }

    function test_processExit_requestedSharedGtLocked() external {
        vm.startPrank(pm);
        withdrawalManager.addShares(3, lp);
        vm.expectRevert("WM:PE:INVALID_SHARES");
        withdrawalManager.processExit(4, lp);
    }

    function test_processExit_requestedSharedLtLocked() external {
        vm.startPrank(pm);
        withdrawalManager.addShares(3, lp);
        vm.expectRevert("WM:PE:INVALID_SHARES");
        withdrawalManager.processExit(2, lp);
    }

    function test_processExit_noRequest() external {
        vm.prank(pm);
        vm.expectRevert("WM:PE:NO_REQUEST");
        withdrawalManager.processExit(0, lp);
    }

    function test_processExit_preWindow() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks - 1);
        vm.prank(pm);
        vm.expectRevert("WM:PE:NOT_IN_WINDOW");
        withdrawalManager.processExit(1, lp);
    }

    function test_processExit_postWindow() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        vm.warp(start + 2 weeks + 2 days);

        vm.prank(pm);
        vm.expectRevert("WM:PE:NOT_IN_WINDOW");
        withdrawalManager.processExit(1, lp);
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
        withdrawalManager.processExit(1, lp);
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

        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(1, lp);

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
        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(2, lp);

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

        ( uint256 redeemableShares, uint256 resultingAssets ) = withdrawalManager.processExit(1, lp);

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

contract LockedLiquidityTests is TestBase {

    address internal pm;

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
        withdrawalManager.processExit(1, lp);

        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

    function test_lockedLiquidity_unrealizedLosses() external {
        poolManager.__setTotalAssets(2);
        poolManager.__setUnrealizedLosses(1);

        vm.warp(start + 2 weeks);
        assertEq(withdrawalManager.lockedLiquidity(), 1);

        vm.prank(pm);
        withdrawalManager.processExit(1, lp);

        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

}

contract ProcessExitWithMultipleUsers is TestBase {

    address internal lp2;
    address internal lp3;

    function setUp() public override{
        super.setUp();

        lp2 = makeAddr("lp2");
        lp3 = makeAddr("lp3");

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
        ( uint256 redeemableShares,  uint256 resultingAssets )  = withdrawalManager.processExit(100, lp);
        asset.burn(address(pool), resultingAssets);
        pool.burn(address(lp),    redeemableShares);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets);

        ( uint256 redeemableShares2, uint256 resultingAssets2 ) = withdrawalManager.processExit(300, lp2);
        asset.burn(address(pool), resultingAssets2);
        pool.burn(address(lp2),   redeemableShares2);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets2);

        ( uint256 redeemableShares3, uint256 resultingAssets3 ) = withdrawalManager.processExit(400, lp3);
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
        asset.mint(address(pool), 240);      // 1/10 assets available
        poolManager.__setTotalAssets(2400);  // 3:1 exchange rate

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
        ( uint256 redeemableShares,  uint256 resultingAssets )  = withdrawalManager.processExit(100, lp);
        asset.burn(address(pool), resultingAssets);
        pool.burn(address(lp),    redeemableShares);
        poolManager.__setTotalAssets(poolManager.totalAssets() - resultingAssets);

        ( uint256 redeemableShares2, uint256 resultingAssets2 ) = withdrawalManager.processExit(300, lp2);
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

contract ViewFunctionTests is TestBase {

    function setUp() public override {
        super.setUp();
    }

    function test_noLockedShares_isInExitWindowCheck() external {
        assertEq(withdrawalManager.exitCycleId(lp),  0);
        assertEq(withdrawalManager.lockedShares(lp), 0);

        assertTrue(!withdrawalManager.isInExitWindow(lp));
    }

    function testFuzz_previewWithdraw_alwaysReturnsZero(address user, uint256 amount) external {
        ( uint256 redeemableAssets_, uint256 resultingShares_ ) = withdrawalManager.previewWithdraw(user, amount);

        assertEq(redeemableAssets_, 0);
        assertEq(resultingShares_,  0);
    }

}
