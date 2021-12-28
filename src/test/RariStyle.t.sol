// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { DSTest }    from "../../lib/ds-test/src/test.sol";
import { MockERC20 } from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { LP }           from "./accounts/LP.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { FundsRecipient } from "./mocks/FundsRecipient.sol";

import { PoolV2 } from "../RariStyle.sol";

interface Vm {
    function expectRevert(bytes calldata) external;
}

contract PoolV2RariTest is DSTest {

    MockERC20    fundsAsset;
    PoolV2       pool;
    PoolDelegate poolDelegate;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 constant WAD = 10 ** 18;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        poolDelegate = new PoolDelegate();

        fundsAsset = new MockERC20("FundsAsset", "FA", 18);
        pool       = new PoolV2(address(fundsAsset), address(poolDelegate));
    }

    function constrictToRange(uint256 input, uint256 min, uint256 max) internal pure returns (uint256 output) {
        return min == max ? max : input % (max - min) + min;
    }

    function test_deposit(uint256 depositAmount) public {
        LP lp = new LP();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        fundsAsset.mint(address(lp), depositAmount);

        assertEq(fundsAsset.balanceOf(address(lp)),        depositAmount);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), 0);
        assertEq(pool.balanceOf(address(lp)),              0);

        vm.expectRevert("P:D:TRANSFER_FROM_FAIL");
        lp.pool_deposit(address(pool), depositAmount);

        lp.erc20_approve(address(fundsAsset), address(pool), depositAmount);
        lp.pool_deposit(address(pool), depositAmount);

        assertEq(fundsAsset.balanceOf(address(lp)),        0);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), depositAmount);
        assertEq(pool.balanceOf(address(lp)),              depositAmount);
    }

    function test_withdraw(uint256 depositAmount) public {
        LP lp = new LP();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        fundsAsset.mint(address(lp), depositAmount);

        lp.erc20_approve(address(fundsAsset), address(pool), depositAmount);
        lp.pool_deposit(address(pool), depositAmount);

        assertEq(fundsAsset.balanceOf(address(lp)),        0);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), depositAmount);
        assertEq(pool.balanceOf(address(lp)),              depositAmount);

        vm.expectRevert(ARITHMETIC_ERROR);  // Arithmetic error
        lp.pool_withdraw(address(pool), depositAmount + 1);
        lp.pool_withdraw(address(pool), depositAmount);


        assertEq(fundsAsset.balanceOf(address(lp)),        depositAmount);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), 0);
        assertEq(pool.balanceOf(address(lp)),              0);
    }

    function test_redeem(uint256 depositAmount) public {
        LP lp = new LP();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        fundsAsset.mint(address(lp), depositAmount);

        lp.erc20_approve(address(fundsAsset), address(pool), depositAmount);
        lp.pool_deposit(address(pool), depositAmount);

        assertEq(fundsAsset.balanceOf(address(lp)),        0);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), depositAmount);
        assertEq(pool.balanceOf(address(lp)),              depositAmount);

        lp.pool_redeem(address(pool), depositAmount);

        assertEq(fundsAsset.balanceOf(address(lp)),        depositAmount);
        assertEq(fundsAsset.balanceOf(address(pool)),      0);
        assertEq(fundsAsset.balanceOf(pool.cashManager()), 0);
        assertEq(pool.balanceOf(address(lp)),              0);
    }

    function test_deployFunds(uint256 depositAmount) public {
        FundsRecipient fundsRecipient  = new FundsRecipient();
        LP             lp              = new LP();
        PoolDelegate   notPoolDelegate = new PoolDelegate();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        fundsAsset.mint(address(lp), depositAmount);

        lp.erc20_approve(address(fundsAsset), address(pool), depositAmount);
        lp.pool_deposit(address(pool), depositAmount);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),      depositAmount);
        assertEq(fundsAsset.balanceOf(address(fundsRecipient)), 0);
        assertEq(pool.principalOut(),                           0);

        vm.expectRevert("P:DF:NOT_PD");
        notPoolDelegate.pool_deployFunds(address(pool), address(fundsRecipient), depositAmount);
        vm.expectRevert("FC:CF:TRANSFER_FAIL");
        poolDelegate.pool_deployFunds(address(pool), address(fundsRecipient), depositAmount + 1);
        poolDelegate.pool_deployFunds(address(pool), address(fundsRecipient), depositAmount);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),      0);
        assertEq(fundsAsset.balanceOf(address(fundsRecipient)), depositAmount);
        assertEq(pool.principalOut(),                           depositAmount);
    }

    function test_claimPrincipal(uint256 depositAmount, uint256 principalAmount) public {
        FundsRecipient fundsRecipient  = new FundsRecipient();
        LP             lp              = new LP();

        depositAmount   = constrictToRange(depositAmount,   1, 1e45);
        principalAmount = constrictToRange(principalAmount, 1, depositAmount);

        _mintFundsAndDeposit(lp, depositAmount);
        poolDelegate.pool_deployFunds(address(pool), address(fundsRecipient), depositAmount);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),      0);
        assertEq(fundsAsset.balanceOf(address(fundsRecipient)), depositAmount);
        assertEq(pool.principalOut(),                           depositAmount);

        fundsRecipient.payPrincipal(address(fundsAsset), address(pool), principalAmount);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),      0);
        assertEq(fundsAsset.balanceOf(pool.principalManager()), principalAmount);
        assertEq(fundsAsset.balanceOf(address(fundsRecipient)), depositAmount - principalAmount);
        assertEq(pool.principalOut(),                           depositAmount);

        pool.claimPrincipal();  // Anyone can claim principal on behalf of the pool

        assertEq(fundsAsset.balanceOf(pool.cashManager()),      principalAmount);
        assertEq(fundsAsset.balanceOf(pool.principalManager()), 0);
        assertEq(fundsAsset.balanceOf(address(fundsRecipient)), depositAmount - principalAmount);
        assertEq(pool.principalOut(),                           depositAmount - principalAmount);
    }

    function test_withdraw_multi_user_interestAccrual() public {
        FundsRecipient fundsRecipient1 = new FundsRecipient();
        FundsRecipient fundsRecipient2 = new FundsRecipient();

        LP lp1 = new LP();
        LP lp2 = new LP();
        LP lp3 = new LP();
        LP lp4 = new LP();

        uint256 depositAmount_lp1 = 2_000_000 * WAD;
        uint256 depositAmount_lp2 = 3_000_000 * WAD;
        uint256 depositAmount_lp3 = 5_000_000 * WAD;
        uint256 deployAmount1     = 1_000_000 * WAD;
        uint256 deployAmount2     = 7_000_000 * WAD;

        _mintFundsAndDeposit(lp1, depositAmount_lp1);
        _mintFundsAndDeposit(lp2, depositAmount_lp2);
        _mintFundsAndDeposit(lp3, depositAmount_lp3);

        // Fund two "loans"
        poolDelegate.pool_deployFunds(address(pool), address(fundsRecipient1), deployAmount1);
        poolDelegate.pool_deployFunds(address(pool), address(fundsRecipient1), deployAmount2);

        /************************************/
        /*** Interest gets paid into Pool ***/
        /************************************/

        assertEq(fundsAsset.balanceOf(pool.cashManager()),  2_000_000 * WAD);
        assertEq(pool.principalOut(),                       8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                     10_000_000 * WAD);
        assertEq(pool.totalSupply(),                       10_000_000 * WAD);
        assertEq(pool.exchangeRate(),                           1.000 ether);

        assertEq(pool.balanceOfUnderlying(address(lp1)), 2_000_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp2)), 3_000_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp3)), 5_000_000 * WAD);

        // Pay back interest on loan 1
        fundsAsset.mint(address(fundsRecipient1),  50_000 * WAD);
        fundsAsset.mint(address(fundsRecipient2), 200_000 * WAD);
        fundsRecipient1.payInterest(address(fundsAsset), address(pool),  50_000 * WAD);
        fundsRecipient2.payInterest(address(fundsAsset), address(pool), 200_000 * WAD);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),  2_250_000 * WAD);
        assertEq(pool.principalOut(),                       8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                     10_250_000 * WAD);
        assertEq(pool.totalSupply(),                       10_000_000 * WAD);
        assertEq(pool.exchangeRate(),                           1.025 ether);  // 2.5% growth in pool size

        // Assert pool equity
        assertEq(pool.balanceOf(address(lp1)) * WAD / pool.totalSupply(), 0.2 ether);
        assertEq(pool.balanceOf(address(lp2)) * WAD / pool.totalSupply(), 0.3 ether);
        assertEq(pool.balanceOf(address(lp3)) * WAD / pool.totalSupply(), 0.5 ether);

        // Assert balances are distributed according to equity
        assertEq(pool.balanceOfUnderlying(address(lp1)), 2_050_000 * WAD);  // 0.250 * 0.2 = 0.05
        assertEq(pool.balanceOfUnderlying(address(lp2)), 3_075_000 * WAD);  // 0.250 * 0.3 = 0.075
        assertEq(pool.balanceOfUnderlying(address(lp3)), 5_125_000 * WAD);  // 0.250 * 0.5 = 0.125

        /**********************************/
        /*** LP1 withdraws full balance ***/
        /**********************************/

        vm.expectRevert(ARITHMETIC_ERROR);
        lp1.pool_withdraw(address(pool), 2_250_000 * WAD);  // Can't withdraw full balance
        vm.expectRevert(ARITHMETIC_ERROR);
        lp1.pool_withdraw(address(pool), 2_050_000 * WAD + 2);  // Can't withdraw more than balance earned (1e-18 neglible for rounding, should investigate)

        assertEq(pool.balanceOf(address(lp1)),           2_000_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp1)), 2_050_000 * WAD);  // 2.5% of 2m is 50k
        assertEq(fundsAsset.balanceOf(address(lp1)),     0);

        lp1.pool_withdraw(address(pool), 2_050_000 * WAD);  // Can't withdraw more than balance earned (1e-18 neglible for rounding)

        assertEq(pool.balanceOf(address(lp1)),           0);
        assertEq(pool.balanceOfUnderlying(address(lp1)), 0);
        assertEq(fundsAsset.balanceOf(address(lp1)),     2_050_000 * WAD);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),    200_000 * WAD);
        assertEq(pool.principalOut(),                       8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                      8_200_000 * WAD);
        assertEq(pool.totalSupply(),                        8_000_000 * WAD);
        assertEq(pool.exchangeRate(),                           1.025 ether);  // Does not change

        // LPs balanceOfUnderlying unaffected by withdrawal
        assertEq(pool.balanceOfUnderlying(address(lp2)), 3_075_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp3)), 5_125_000 * WAD);

        /***********************/
        /*** LP4 enters pool ***/
        /***********************/

        assertEq(pool.balanceOf(address(lp4)),           0);
        assertEq(pool.balanceOfUnderlying(address(lp4)), 0);

        _mintFundsAndDeposit(lp4, 2_050_000 * WAD);

        assertEq(pool.balanceOf(address(lp4)),           2_000_000 * WAD);  // 1.025 units per LP token
        assertEq(pool.balanceOfUnderlying(address(lp4)), 2_050_000 * WAD);

        assertEq(pool.balanceOfUnderlying(address(lp2)), 3_075_000 * WAD);  // Unaffected by deposit
        assertEq(pool.balanceOfUnderlying(address(lp3)), 5_125_000 * WAD);  // Unaffected by deposit

        assertEq(fundsAsset.balanceOf(pool.cashManager()),   2_250_000 * WAD);
        assertEq(pool.principalOut(),                        8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                      10_250_000 * WAD);
        assertEq(pool.totalSupply(),                        10_000_000 * WAD);
        assertEq(pool.exchangeRate(),                            1.025 ether);  // Does not change

        /*****************************************/
        /*** More interest gets paid into pool ***/
        /*****************************************/

        // Pay back interest on loan 1 and 2
        fundsAsset.mint(address(fundsRecipient1), 350_000 * WAD);
        fundsAsset.mint(address(fundsRecipient2), 400_000 * WAD);
        fundsRecipient1.payInterest(address(fundsAsset), address(pool), 350_000 * WAD);
        fundsRecipient2.payInterest(address(fundsAsset), address(pool), 400_000 * WAD);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),   3_000_000 * WAD);
        assertEq(pool.principalOut(),                        8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                      11_000_000 * WAD);
        assertEq(pool.totalSupply(),                        10_000_000 * WAD);
        assertEq(pool.exchangeRate(),                            1.100 ether);

        // Assert pool equity
        assertEq(pool.balanceOf(address(lp2)) * WAD / pool.totalSupply(), 0.3 ether);
        assertEq(pool.balanceOf(address(lp3)) * WAD / pool.totalSupply(), 0.5 ether);
        assertEq(pool.balanceOf(address(lp4)) * WAD / pool.totalSupply(), 0.2 ether);

        // Assert balances are distributed according to equity
        assertEq(pool.balanceOfUnderlying(address(lp2)), 3_300_000 * WAD);  // 3.3 - 3.075 = 0.225 == 0.750 * 0.3
        assertEq(pool.balanceOfUnderlying(address(lp3)), 5_500_000 * WAD);  // 5.5 - 5.125 = 0.375 == 0.750 * 0.5
        assertEq(pool.balanceOfUnderlying(address(lp4)), 2_200_000 * WAD);  // 2.2 - 2.050 = 0.150 == 0.750 * 0.2

        /**********************************/
        /*** LP4 withdraws full balance ***/
        /**********************************/

        vm.expectRevert(ARITHMETIC_ERROR);
        lp1.pool_withdraw(address(pool), 2_200_000 * WAD + 2);  // Can't withdraw more than balance earned (1e-18 neglible for rounding, should investigate)

        assertEq(pool.balanceOf(address(lp4)),           2_000_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp4)), 2_200_000 * WAD);
        assertEq(fundsAsset.balanceOf(address(lp4)),     0);

        lp4.pool_withdraw(address(pool), 2_200_000 * WAD);

        assertEq(pool.balanceOf(address(lp4)),           0);
        assertEq(pool.balanceOfUnderlying(address(lp4)), 0);
        assertEq(fundsAsset.balanceOf(address(lp4)),     2_200_000 * WAD);

        assertEq(fundsAsset.balanceOf(pool.cashManager()),    800_000 * WAD);
        assertEq(pool.principalOut(),                       8_000_000 * WAD);
        assertEq(pool.totalHoldings(),                      8_800_000 * WAD);
        assertEq(pool.exchangeRate(),                           1.100 ether);  // Does not change

        // Prove that deposit does not change equity
        lp4.erc20_approve(address(fundsAsset), address(pool), 2_200_000 * WAD);
        lp4.pool_deposit(address(pool), 2_200_000 * WAD);

        assertEq(pool.balanceOf(address(lp4)),           2_000_000 * WAD);
        assertEq(pool.balanceOfUnderlying(address(lp4)), 2_200_000 * WAD);
        assertEq(fundsAsset.balanceOf(address(lp4)),     0);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _mintFundsAndDeposit(LP lp, uint256 amount) internal {
        fundsAsset.mint(address(lp), amount);
        lp.erc20_approve(address(fundsAsset), address(pool), amount);
        lp.pool_deposit(address(pool), amount);
    }
}