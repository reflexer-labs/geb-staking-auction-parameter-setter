// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./GebSurplusAuctionInitialParamSetter.sol";

contract GebSurplusAuctionInitialParamSetterTest is DSTest {
    GebSurplusAuctionInitialParamSetter setter;

    function setUp() public {
        setter = new GebSurplusAuctionInitialParamSetter();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
