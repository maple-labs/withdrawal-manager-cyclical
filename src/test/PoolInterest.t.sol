// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../lib/erc20/contracts/test/mocks/MockERC20.sol";

import { CashManager } from "../CashManager.sol";
import { PoolV2 }      from "../PoolV2.sol";

import { LP }           from "./accounts/LP.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { FundsRecipient } from "./mocks/FundsRecipient.sol";

interface Vm {
    function expectRevert(bytes calldata) external;
    function warp(uint256 timestamp) external;
}

contract PoolInterestTest is TestUtils {

    MockERC20    fundsAsset;
    PoolV2       pool;
    PoolDelegate poolDelegate;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 constant WAD = 10 ** 18;

    function setUp() public {
        poolDelegate = new PoolDelegate();

        fundsAsset = new MockERC20("FundsAsset", "FA", 18);
        pool       = new PoolV2(address(fundsAsset), address(poolDelegate));

        vm.warp(1641328389);
    }

    // Corresponding calculations: https://www.desmos.com/calculator/gb8lfzqdun
    function test_interest_streaming_simple() public {
        LP lp = new LP();

        uint256 start = block.timestamp;

        FundsRecipient loan1 = new FundsRecipient();
        FundsRecipient loan2 = new FundsRecipient();
        FundsRecipient loan3 = new FundsRecipient();
        FundsRecipient loan4 = new FundsRecipient();

        _mintFundsAndDeposit(lp, 80 ether);

        poolDelegate.pool_deployFunds(address(pool), address(loan1), 10 ether);
        poolDelegate.pool_deployFunds(address(pool), address(loan2), 20 ether);
        poolDelegate.pool_deployFunds(address(pool), address(loan3), 10 ether);
        poolDelegate.pool_deployFunds(address(pool), address(loan4), 40 ether);

        CashManager cashManager = CashManager(pool.cashManager());

        assertEq(fundsAsset.balanceOf(address(cashManager)), 0);
        assertEq(pool.totalHoldings(),                       80 ether);

        assertEq(cashManager.freeCash(),                     0);
        assertEq(cashManager.issuanceInterval(),             2);
        assertEq(cashManager.issuanceRate(),                 0);
        assertEq(cashManager.lastUpdated(),                  0);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 0);
        assertEq(cashManager.unlockedBalance(),              0);

        // Make an interest payment on day zero for 1 ether (all payments issue over 2 days)
        loan1.payInterest(address(fundsAsset), address(pool), 1 ether);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 1 ether);
        assertEq(pool.totalHoldings(),                       80 ether);

        assertEq(cashManager.freeCash(),                     0);
        assertEq(cashManager.issuanceRate(),                 0.5 ether);
        assertEq(cashManager.lastUpdated(),                  start);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 1 ether);
        assertEq(cashManager.unlockedBalance(),              0);

        // Warp to day 1
        vm.warp(block.timestamp + 1);  // Seconds == days to make math easy

        assertEq(fundsAsset.balanceOf(address(cashManager)), 1 ether);
        assertEq(pool.totalHoldings(),                       80.5 ether);

        // All cash manager state is kept constant (will not assert this after subsequent warps)
        assertEq(cashManager.freeCash(),                     0);
        assertEq(cashManager.issuanceRate(),                 0.5 ether);
        assertEq(cashManager.lastUpdated(),                  start);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 1 ether);
        assertEq(cashManager.unlockedBalance(),              0.5 ether);  // One day has passed, 0.5 ether is unlocked

        // Make an interest payment on day 1 for 2 ether
        loan2.payInterest(address(fundsAsset), address(pool), 2 ether);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 3 ether);
        assertEq(pool.totalHoldings(),                       80.5 ether);

        assertEq(cashManager.freeCash(),                     0.5 ether);   // Free cash is set to unlocked balance
        assertEq(cashManager.issuanceRate(),                 1.25 ether);  // Issuance rate is increased
        assertEq(cashManager.lastUpdated(),                  start + 1);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 3 ether);
        assertEq(cashManager.unlockedBalance(),              0.5 ether);

        // Make an interest payment on day 1 for 1 ether
        loan3.payInterest(address(fundsAsset), address(pool), 1 ether);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 4 ether);
        assertEq(pool.totalHoldings(),                       80.5 ether);

        assertEq(cashManager.freeCash(),                     0.5 ether);   // Free cash is set to unlocked balance (same since no time passes)
        assertEq(cashManager.issuanceRate(),                 1.75 ether);  // Issuance rate is increased
        assertEq(cashManager.lastUpdated(),                  start + 1);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 4 ether);
        assertEq(cashManager.unlockedBalance(),              0.5 ether);

        // Warp to day 2
        vm.warp(start + 2);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 4 ether);
        assertEq(pool.totalHoldings(),                       82.25 ether);
        assertEq(cashManager.unlockedBalance(),              2.25 ether);

        // Make an interest payment on day 2 for 4 ether
        loan4.payInterest(address(fundsAsset), address(pool), 1 ether);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 5 ether);
        assertEq(pool.totalHoldings(),                       82.25 ether);

        assertEq(cashManager.freeCash(),                     2.25 ether);   // Free cash is set to unlocked balance
        assertEq(cashManager.issuanceRate(),                 1.375 ether);  // Issuance rate is reduced
        assertEq(cashManager.lastUpdated(),                  start + 2);
        assertEq(cashManager.totalUnlockedAtEndOfInterval(), 5 ether);
        assertEq(cashManager.unlockedBalance(),              2.25 ether);

        // Warp to day 3 (No payments)
        vm.warp(start + 3);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 5 ether);
        assertEq(pool.totalHoldings(),                       83.625 ether);
        assertEq(cashManager.unlockedBalance(),              3.625 ether);

        // Warp to day 4 (No payments, all payments streams ended)
        vm.warp(start + 4);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 5 ether);
        assertEq(pool.totalHoldings(),                       85 ether);
        assertEq(cashManager.unlockedBalance(),              5 ether);

        // Warp to day 5 (Past end of payments streams, should not change)
        vm.warp(start + 5);

        assertEq(fundsAsset.balanceOf(address(cashManager)), 5 ether);
        assertEq(pool.totalHoldings(),                       85 ether);
        assertEq(cashManager.unlockedBalance(),              5 ether);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _mintFundsAndDeposit(LP lp, uint256 amount) internal {
        fundsAsset.mint(address(lp), amount);
        lp.erc20_approve(address(fundsAsset), pool.cashManager(), amount);
        lp.pool_deposit(address(pool), amount);
    }
}