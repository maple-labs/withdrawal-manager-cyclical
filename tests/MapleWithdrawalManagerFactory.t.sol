// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test }      from "../modules/forge-std/src/Test.sol";
import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MapleWithdrawalManager }            from "../contracts/MapleWithdrawalManager.sol";
import { MapleWithdrawalManagerFactory }     from "../contracts/MapleWithdrawalManagerFactory.sol";
import { MapleWithdrawalManagerInitializer } from "../contracts/MapleWithdrawalManagerInitializer.sol";

import { MockGlobals, MockPool } from "./mocks/Mocks.sol";

contract MapleWithdrawalManagerFactoryTests is Test {

    address internal governor;
    address internal poolDelegate;

    address internal implementation;
    address internal initializer;

    MockERC20   internal asset;
    MockGlobals internal globals;
    MockPool    internal pool;

    MapleWithdrawalManagerFactory internal factory;

    function setUp() external {
        governor     = makeAddr("governor");
        poolDelegate = makeAddr("poolDelegate");
        
        implementation = address(new MapleWithdrawalManager());
        initializer    = address(new MapleWithdrawalManagerInitializer());
        
        asset   = new MockERC20("Wrapped Ether", "WETH", 18);
        globals = new MockGlobals(address(governor));
        pool    = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), poolDelegate);

        vm.startPrank(governor);
        factory = new MapleWithdrawalManagerFactory(address(globals));
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

        MapleWithdrawalManager withdrawalManager_ = MapleWithdrawalManager(factory.createInstance(calldata_, "SALT"));

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
