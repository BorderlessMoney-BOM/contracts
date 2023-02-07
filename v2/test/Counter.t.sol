// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Counter.sol";
import {BaseSetup} from "./BaseSetup.sol";

contract CounterTest is Test, BaseSetup {
    Counter public counter;

    function setUp() public virtual override{
        BaseSetup.setUp();
        vm.prank(owner);
        counter = new Counter();

        counter.setNumber(0);
    }

    function testIncrement() public {
        vm.prank(bob);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testSetNumber(uint256 x) public {
        vm.prank(alise);
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
