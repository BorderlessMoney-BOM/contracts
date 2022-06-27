// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./IStrategy.sol";

import "hardhat/console.sol";

contract AaveUSDCStrategy is IStrategy, AccessControl {
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IERC20 _aPolUsdc;
    IPool _pool;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;

    constructor(
        address usdc,
        address aPolUsdc,
        address pool
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _usdc = IERC20(usdc);
        _aPolUsdc = IERC20(aPolUsdc);
        _pool = IPool(pool);
    }

    function delegate(address sdgAddress, uint256 amount)
        external
        onlyRole(VAULT_ROLE)
    {
        console.log("Delegating to Aave USDC", amount);

        _usdc.approve(address(_pool), amount);
        _pool.supply(address(_usdc), amount, address(this), 0);
        _delegatedAmount[sdgAddress] += amount;

        emit Delegate(sdgAddress, amount);
    }

    function withdraw(address sdgAddress, uint256 amount)
        external
        onlyRole(VAULT_ROLE)
    {
        _pool.withdraw(address(_usdc), amount, address(this));
        _usdc.transfer(msg.sender, amount);
        _withdrawnAmount[sdgAddress] += amount;

        emit Withdraw(sdgAddress, amount);
    }

    function totalRewards(address sdgAddress)
        external
        view
        returns (uint256 amount)
    {}

    function collectedRewards(address sdgAddress)
        external
        view
        returns (uint256 amount)
    {}

    function collectRewards(address sdgAddress, uint256 amount)
        external
        override
    {}
}
