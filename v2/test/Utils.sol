// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

//common utilities for forge tests
contract Utils is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() external returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    function createUsers(uint256 userNum) external returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = this.getNextUserAddress();
            vm.deal(user, 10000 ether);
            users[i] = user;
        }
        return users;
    }
}
