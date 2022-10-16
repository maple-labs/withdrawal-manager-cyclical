// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { Address, TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }          from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { WithdrawalManager }            from "../contracts/WithdrawalManager.sol";
import { WithdrawalManagerFactory }     from "../contracts/WithdrawalManagerFactory.sol";
import { WithdrawalManagerInitializer } from "../contracts/WithdrawalManagerInitializer.sol";

import { MockGlobals, MockPool } from "./mocks/Mocks.sol";

contract WithdrawalManagerFactoryTests is TestUtils {

    address governor;
    address poolDelegate;

    address implementation;
    address initializer;

    MockERC20   asset;
    MockGlobals globals;
    MockPool    pool;

    WithdrawalManagerFactory factory;

    function setUp() external {
        governor     = address(new Address());
        poolDelegate = address(new Address());

        implementation = address(new WithdrawalManager());
        initializer    = address(new WithdrawalManagerInitializer());

        asset   = new MockERC20("Wrapped Ether", "WETH", 18);
        globals = new MockGlobals(address(governor));
        pool    = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), poolDelegate);

        vm.startPrank(governor);
        factory = new WithdrawalManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.setValidPoolDeployer(address(this), true);
        vm.stopPrank();
    }

    function test_createInstance_notPoolDeployer() external {
        bytes memory calldata_ = abi.encode(address(pool), 1, 1);

        MockGlobals(globals).setValidPoolDeployer(address(this), false);
        vm.expectRevert("WMF:CI:NOT_DEPLOYER");
        factory.createInstance(calldata_, "SALT");

        MockGlobals(globals).setValidPoolDeployer(address(this), true);
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_zeroPool() external {
        bytes memory calldata_ = abi.encode(address(0), 1, 1);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_zeroWindow() external {
        bytes memory calldata_ = abi.encode(address(pool), 1, 0);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_windowOutOfBounds() external {
        bytes memory calldata_ = abi.encode(address(pool), 1, 2);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function testFail_createInstance_collision() external {
        bytes memory calldata_ = abi.encode(address(pool), 1, 1);

        factory.createInstance(calldata_, "SALT");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_success() external {
        bytes memory calldata_ = abi.encode(address(pool), 1, 1);

        WithdrawalManager withdrawalManager_ = WithdrawalManager(factory.createInstance(calldata_, "SALT"));

        (
            uint64 initialCycleId_,
            uint64 initialCycleTime_,
            uint64 cycleDuration_,
            uint64 windowDuration_
        ) = withdrawalManager_.cycleConfigs(0);

        assertEq(withdrawalManager_.pool(),           address(pool));
        assertEq(withdrawalManager_.latestConfigId(), 0);

        assertEq(initialCycleId_,   1);
        assertEq(initialCycleTime_, block.timestamp);
        assertEq(cycleDuration_,    1);
        assertEq(windowDuration_,   1);
    }

}
