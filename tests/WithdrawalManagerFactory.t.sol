// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { TestUtils } from "../modules/contract-test-utils/contracts/test.sol";

import { WithdrawalManager }            from "../contracts/WithdrawalManager.sol"; 
import { WithdrawalManagerFactory }     from "../contracts/WithdrawalManagerFactory.sol"; 
import { WithdrawalManagerInitializer } from "../contracts/WithdrawalManagerInitializer.sol"; 

import { MapleGlobalsMock, MockPool } from "./mocks/mocks.sol";

contract WithdrawalManagerFactoryBase is TestUtils {

    address constant ASSET = address(1);
    address constant PD    = address(2);

    MapleGlobalsMock         globals;
    MockPool                 pool;
    WithdrawalManagerFactory factory;

    address implementation;
    address initializer;

    function setUp() virtual public {
        globals = new MapleGlobalsMock(address(this), address(0), uint256(0), uint256(0));
        factory = new WithdrawalManagerFactory(address(globals));
        pool    = new MockPool("Pool", "Pool", 18, ASSET, PD);

        implementation = address(new WithdrawalManager());
        initializer    = address(new WithdrawalManagerInitializer());

        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
    }

}

contract CreateInstanceTest is WithdrawalManagerFactoryBase {

    function test_createInstance() external {
        address asset_ = ASSET;
        address pool_  =  address(pool);

        uint256 periodStart_        = 1641164400;  // 1st Monday of 2022
        uint256 periodDuration_     = 48 hours;
        uint256 periodFrequency_    = 1 weeks;
        uint256 cooldownMultiplier_ = 1;

        bytes memory arguments_ = WithdrawalManagerInitializer(initializer).encodeArguments(asset_, pool_, periodStart_, periodDuration_, periodFrequency_, cooldownMultiplier_);

        address withdrawalManagerAddress = factory.createInstance(arguments_, "SALT"); 

        assertTrue(factory.isInstance(withdrawalManagerAddress));

        WithdrawalManager withdrawalManager = WithdrawalManager(withdrawalManagerAddress);

        address poolManager = pool.manager();

        assertEq(withdrawalManager.implementation(),  implementation);
        assertEq(withdrawalManager.factory(),         address(factory));
        assertEq(withdrawalManager.asset(),           ASSET);
        assertEq(withdrawalManager.pool(),            address(pool));
        assertEq(withdrawalManager.poolManager(),     poolManager);
        assertEq(withdrawalManager.periodStart(),     periodStart_);
        assertEq(withdrawalManager.periodDuration(),  periodDuration_);
        assertEq(withdrawalManager.periodFrequency(), periodFrequency_);
        assertEq(withdrawalManager.periodCooldown(),  periodFrequency_ * cooldownMultiplier_);

        assertEq(pool.allowance(address(withdrawalManager),poolManager), type(uint256).max);
    }

}

contract CreateInstanceFailureTest is WithdrawalManagerFactoryBase {
    
    address _asset = ASSET;

    uint256 _periodStart        = 1641164400;  // 1st Monday of 2022
    uint256 _periodDuration     = 48 hours;
    uint256 _periodFrequency    = 1 weeks;
    uint256 _cooldownMultiplier = 1;

    bytes32 _salt = "SALT";

    function test_createInstance_durationLargerThanFrequency() external {
        _periodDuration = 2 weeks;
        
        bytes memory arguments_ = WithdrawalManagerInitializer(initializer).encodeArguments(_asset, address(pool), _periodStart, _periodDuration, _periodFrequency, _cooldownMultiplier);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(arguments_, _salt);
    }

    function test_createInstance_zeroCooldown() external {
        _cooldownMultiplier = 0;
        
        bytes memory arguments_ = WithdrawalManagerInitializer(initializer).encodeArguments(_asset, address(pool), _periodStart, _periodDuration, _periodFrequency, _cooldownMultiplier);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(arguments_, _salt);
    }

    function test_createInstance_zeroPool() external {
        bytes memory arguments_ = WithdrawalManagerInitializer(initializer).encodeArguments(_asset, address(0), _periodStart, _periodDuration, _periodFrequency, _cooldownMultiplier);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(arguments_, _salt);
    }

}
