// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Utils} from "./Utils.sol";

contract BaseSetup is Utils {
    address owner;
    address bob;
    address alise;
    address[] users;

    function setUp() public virtual {
        Utils utils = new Utils();
        users = utils.createUsers(3);

        owner = users[0];
        vm.label(owner, "Owner");
        bob = users[1];
        vm.label(bob, "Bob");
        alise = users[2];
        vm.label(alise, "Alise");
    }
}
