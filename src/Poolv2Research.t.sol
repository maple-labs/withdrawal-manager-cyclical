// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Poolv2Research.sol";

contract Poolv2ResearchTest is DSTest {
    Poolv2Research research;

    function setUp() public {
        research = new Poolv2Research();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
