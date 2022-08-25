// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./IStrategy.sol";

contract AaveUSDCStrategy is IStrategy, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IERC20 _aPolUsdc;
    IPool _pool;
    EnumerableSet.AddressSet _sdgs;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _previousTotalRewards;
    mapping(address => uint256) _materializedRewards;

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

    function _materializeRewards() internal {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            address sdg = _sdgs.at(i);
            _materializedRewards[sdg] = availableRewards(sdg);
            _previousTotalRewards[sdg] = totalRewards();
        }
    }

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        _materializeRewards();

        _sdgs.add(msg.sender);

        _previousTotalRewards[msg.sender] =
            _aPolUsdc.balanceOf(address(this)) -
            totalBalance();

        _usdc.transferFrom(msg.sender, address(this), amount);
        _usdc.approve(address(_pool), amount);
        _pool.supply(address(_usdc), amount, address(this), 0);
        _delegatedAmount[msg.sender] += amount;

        emit Delegate(amount);
    }

    function undelegate(uint256 amount)
        external
        onlyRole(VAULT_ROLE)
        returns (uint256)
    {
        _materializeRewards();

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
        _withdrawnAmount[msg.sender] += amount;

        emit Withdraw(amount);

        return amount;
    }

    function availableRewards(address sdg)
        public
        view
        returns (uint256 amount)
    {
        return
            ((totalRewards() - _previousTotalRewards[sdg]) * balanceOf(sdg)) /
            totalBalance() +
            _materializedRewards[sdg];
    }

    function collectedRewards(address sdg)
        public
        view
        returns (uint256 amount)
    {
        return _collectedRewards[sdg];
    }

    function collectRewards(uint256 amount)
        external
        override
        onlyRole(VAULT_ROLE)
        returns (uint256)
    {
        if (amount > availableRewards(msg.sender)) {
            revert InvalidRewardsAmount(amount, availableRewards(msg.sender));
        }
        _collectedRewards[msg.sender] += amount;

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

        _withdrawnAmount[msg.sender] += amount;
        _previousTotalRewards[msg.sender] = totalRewards();

        emit CollectRewards(amount);

        return amount;
    }

    function balanceOf(address sdg) public view returns (uint256 amount) {
        return _delegatedAmount[sdg] - _withdrawnAmount[sdg];
    }

    function totalBalance() public view returns (uint256 amount) {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            amount += balanceOf(_sdgs.at(i));
        }
        return amount;
    }

    function totalRewards() public view returns (uint256 amount) {
        return _aPolUsdc.balanceOf(address(this)) - totalBalance();
    }

    function totalCollectedRewards() public view returns (uint256 amount) {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            amount += collectedRewards(_sdgs.at(i));
        }
        return amount;
    }
}
