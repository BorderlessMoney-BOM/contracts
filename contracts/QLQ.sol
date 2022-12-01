// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract QLQ is ERC20 {
    constructor() ERC20("Qualquer", "QLQ") {
        _mint(msg.sender, 1_000 * 10 ** decimals());
    }
}
