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

    uint256 _delegatedAmount;
    uint256 _withdrawnAmount;
    uint256 _collectedRewards;

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

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        console.log("[AaveUSDC] Delegating to Aave USDC", amount);

        _usdc.transferFrom(msg.sender, address(this), amount);
        _usdc.approve(address(_pool), amount);
        _pool.supply(address(_usdc), amount, address(this), 0);
        _delegatedAmount += amount;

        emit Delegate(amount);
    }

    function undelegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        _pool.withdraw(address(_usdc), amount, address(this));
        bool sent = _usdc.transfer(msg.sender, amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                amount
            );
        }
        _withdrawnAmount += amount;

        emit Withdraw(amount);
    }

    function totalRewards() public view returns (uint256 amount) {
        uint256 aPolBalance = _aPolUsdc.balanceOf(address(this));
        return aPolBalance - balance();
    }

    function collectedRewards() external view returns (uint256 amount) {
        return _collectedRewards;
    }

    function collectRewards(uint256 amount)
        external
        override
        onlyRole(VAULT_ROLE)
    {
        if (amount > totalRewards()) {
            revert InvalidRewardsAmount(amount, totalRewards());
        }
        _collectedRewards += amount;

        _pool.withdraw(address(_usdc), amount, address(this));
        bool sent = _usdc.transfer(msg.sender, amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                amount
            );
        }

        emit CollectRewards(amount);
    }

    function balance() public view returns (uint256 amount) {
        return _delegatedAmount - _withdrawnAmount;
    }
}
