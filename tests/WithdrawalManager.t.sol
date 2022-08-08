// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { Address, TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }          from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { WithdrawalManager }            from "../contracts/WithdrawalManager.sol";
import { WithdrawalManagerFactory }     from "../contracts/WithdrawalManagerFactory.sol";
import { WithdrawalManagerInitializer } from "../contracts/WithdrawalManagerInitializer.sol";

import { MockGlobals, MockPool, MockWithdrawalManagerMigrator } from "./mocks/Mocks.sol";

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

    MockERC20   asset;
    MockGlobals globals;
    MockPool    pool;

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
        globals = new MockGlobals(address(governor));
        asset   = new MockERC20("Wrapped Ether", "WETH", 18);
        pool    = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), admin);

        // Set the exchange rate to 2 assets per share.
        pool.__setSharePrice(2);

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

    function test_upgrade_upgradeFailed() external {
        vm.prank(admin);
        vm.expectRevert("MPF:UI:FAILED");
        withdrawalManager.upgrade(2, "1");
    }

    function test_upgrade_success() external {
        assertEq(withdrawalManager.implementation(), implementation);
        assertEq(withdrawalManager.pool(),           address(pool));

        vm.prank(admin);
        withdrawalManager.upgrade(2, abi.encode(address(0)));

        assertEq(withdrawalManager.implementation(), newImplementation);
        assertEq(withdrawalManager.pool(),           address(0));
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

    function setUp() public override {
        super.setUp();

        vm.startPrank(lp);
        pool.mint(lp, 2);
        pool.approve(address(withdrawalManager), 2);
        vm.stopPrank();
    }

    function test_addShares_pendingRequest() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks - 1 seconds);
        vm.prank(lp);
        vm.expectRevert("WM:AS:WITHDRAWAL_PENDING");
        withdrawalManager.addShares(1);
    }

    function test_addShares_emptyRequest() external {
        vm.prank(lp);
        vm.expectRevert("WM:AS:NO_OP");
        withdrawalManager.addShares(0);
    }

    function test_addShares_createRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);
    }

    function test_addShares_refreshRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        withdrawalManager.addShares(0);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);
    }

    function test_addShares_increaseRequest() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 2);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 2);
    }

    function test_addShares_delayedUpdate() external {
        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);

        vm.warp(start + 3 weeks);
        vm.prank(lp);
        withdrawalManager.addShares(0);

        assertEq(withdrawalManager.exitCycleId(lp),     6);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(6), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);
    }

    function test_addShares_failedTransfer() external {
        vm.prank(lp);
        vm.expectRevert("WM:AS:TRANSFER_FAIL");
        withdrawalManager.addShares(3);
    }

}

contract RemoveSharesTests is WithdrawalManagerTestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(lp);
        pool.mint(lp, 2);
        pool.approve(address(withdrawalManager), 2);
        vm.stopPrank();
    }

    function test_removeShares_pendingRequest() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks - 1 seconds);
        vm.prank(lp);
        vm.expectRevert("WM:RS:WITHDRAWAL_PENDING");
        withdrawalManager.removeShares(1);
    }

    function test_removeShares_zeroShares() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        vm.expectRevert("WM:RS:SHARES_OOB");
        withdrawalManager.removeShares(0);
    }

    function test_removeShares_sharesUnderflow() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        vm.expectRevert("WM:RS:SHARES_OOB");
        withdrawalManager.removeShares(2);
    }

    function test_removeShares_decreaseRequest() external {
        vm.prank(lp);
        withdrawalManager.addShares(2);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 2);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        withdrawalManager.removeShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     5);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);
    }

    function test_removeShares_cancelRequest() external {
        vm.prank(lp);
        withdrawalManager.addShares(2);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 2);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        withdrawalManager.removeShares(2);

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);
    }

    function test_removeShares_delayedUpdate() external {
        vm.prank(lp);
        withdrawalManager.addShares(2);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(5), 0);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 2);

        vm.warp(start + 3 weeks);
        vm.prank(lp);
        withdrawalManager.removeShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     6);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(6), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);
    }

    function test_removeShares_failedTransfer() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        pool.burn(address(withdrawalManager), 1);

        vm.warp(start + 2 weeks);
        vm.prank(lp);
        vm.expectRevert("WM:RS:TRANSFER_FAIL");
        withdrawalManager.removeShares(1);
    }

}

contract WithdrawTests is WithdrawalManagerTestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(lp);
        pool.mint(lp, 3);
        pool.approve(address(withdrawalManager), 3);
        vm.stopPrank();
    }

    function test_withdraw_notPool() external {
        vm.expectRevert("WM:W:NOT_POOL");
        withdrawalManager.withdraw(lp, 0);
    }

    function test_withdraw_noRequest() external {
        vm.prank(address(pool));
        vm.expectRevert("WM:W:NO_REQUEST");
        withdrawalManager.withdraw(lp, 0);
    }

    function test_withdraw_preWindow() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks - 1);
        vm.prank(address(pool));
        vm.expectRevert("WM:W:NOT_IN_WINDOW");
        withdrawalManager.withdraw(lp, 0);
    }

    function test_withdraw_postWindow() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        vm.warp(start + 2 weeks + 2 days);

        vm.prank(address(pool));
        vm.expectRevert("WM:W:NOT_IN_WINDOW");
        withdrawalManager.withdraw(lp, 0);
    }

    function test_withdraw_fullWithdrawal() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 1);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 2);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 0);

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        assertEq(asset.balanceOf(lp),            2);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_noLiquidity() external {
        vm.prank(lp);
        withdrawalManager.addShares(1);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 1);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 1);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 0);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 0);

        assertEq(withdrawalManager.exitCycleId(lp),     4);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 1);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 1);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_partialWithdrawal() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(2);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    2);
        assertEq(withdrawalManager.totalCycleShares(3), 2);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 2);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 2);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 0);

        assertEq(withdrawalManager.exitCycleId(lp),     4);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);

        assertEq(asset.balanceOf(lp),            2);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_partialReduction() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(3);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    3);
        assertEq(withdrawalManager.totalCycleShares(3), 3);
        assertEq(withdrawalManager.totalCycleShares(4), 0);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 3);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 2);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 1);

        assertEq(withdrawalManager.exitCycleId(lp),     4);
        assertEq(withdrawalManager.lockedShares(lp),    1);
        assertEq(withdrawalManager.totalCycleShares(3), 0);
        assertEq(withdrawalManager.totalCycleShares(4), 1);

        assertEq(pool.balanceOf(lp), 1);
        assertEq(pool.balanceOf(wm), 1);

        assertEq(asset.balanceOf(lp),            2);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_partialCancellation() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(3);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    3);
        assertEq(withdrawalManager.totalCycleShares(3), 3);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 3);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 2);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 2);

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);
        assertEq(pool.balanceOf(wm), 0);

        assertEq(asset.balanceOf(lp),            2);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_partialOverflow() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(3);

        assertEq(withdrawalManager.exitCycleId(lp),     3);
        assertEq(withdrawalManager.lockedShares(lp),    3);
        assertEq(withdrawalManager.totalCycleShares(3), 3);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(pool.balanceOf(wm), 3);

        assertEq(asset.balanceOf(lp),            0);
        assertEq(asset.balanceOf(address(pool)), 2);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        withdrawalManager.withdraw(lp, 3);  // One more share than available after redemption.

        assertEq(withdrawalManager.exitCycleId(lp),     0);
        assertEq(withdrawalManager.lockedShares(lp),    0);
        assertEq(withdrawalManager.totalCycleShares(3), 0);

        assertEq(pool.balanceOf(lp), 2);  // Instead of reverting, just gives max amount of LP tokens.
        assertEq(pool.balanceOf(wm), 0);

        assertEq(asset.balanceOf(lp),            2);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_withdraw_lostShares() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(1);

        pool.burn(address(withdrawalManager), 1);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        vm.expectRevert(ARITHMETIC_ERROR);
        withdrawalManager.withdraw(lp, 0);
    }

    function test_withdraw_failedTransfer() external {
        asset.mint(address(pool), 2);

        vm.prank(lp);
        withdrawalManager.addShares(2);

        pool.burn(address(withdrawalManager), 1);

        vm.warp(start + 2 weeks);
        vm.prank(address(pool));
        vm.expectRevert("WM:W:TRANSFER_FAIL");
        withdrawalManager.withdraw(lp, 1);
    }

}
