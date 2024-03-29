// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

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

    uint256 _supply;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _shares;

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

    function _getPricePerFullShare() internal view returns (uint256) {
        return
            _totalSupply() == 0
                ? 1e18
                : (targetBalance() * 1e18) / _totalSupply();
    }

    function _totalSupply() internal view returns (uint256) {
        return _supply;
    }

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        _sdgs.add(msg.sender);

        uint256 _before = targetBalance();
        _usdc.transferFrom(msg.sender, address(this), amount);
        _usdc.approve(address(_pool), amount);
        _pool.supply(address(_usdc), amount, address(this), 0);
        uint256 _after = targetBalance();

        amount = _after - _before;

        uint256 shares = 0;
        if (_totalSupply() == 0) {
            shares = amount;
        } else {
            shares = (amount * _totalSupply()) / _before;
        }

        _delegatedAmount[msg.sender] += amount;
        _shares[msg.sender] += shares;
        _supply += shares;

        emit Delegate(msg.sender, amount);
    }

    function undelegate(uint256 amount)
        external
        onlyRole(VAULT_ROLE)
        returns (uint256)
    {
        if (amount > balanceOf(msg.sender)) {
            amount = balanceOf(msg.sender);
        }
        uint256 shares = (amount * _totalSupply()) / targetBalance();
        if (shares > _shares[msg.sender]) {
            shares = _shares[msg.sender];
            amount = (shares * targetBalance()) / _totalSupply();
        }

        _shares[msg.sender] -= shares;
        _supply -= shares;

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

        emit Withdraw(msg.sender, amount);

        return amount;
    }

    function availableRewards(address sdg)
        public
        view
        returns (uint256 amount)
    {
        uint256 _before = balanceOf(sdg);
        uint256 _after = (_shares[sdg] * _getPricePerFullShare()) / 1e18;

        if (_before > _after) {
            return 0;
        }
        return _after - _before;
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
            amount = availableRewards(msg.sender);
        }

        uint256 shares = (amount * _totalSupply()) / targetBalance();

        _shares[msg.sender] -= shares;
        _supply -= shares;

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

        _collectedRewards[msg.sender] += amount;

        emit CollectRewards(msg.sender, amount);

        return amount;
    }

    function targetBalance() public view returns (uint256) {
        return _aPolUsdc.balanceOf(address(this));
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
        return
            _aPolUsdc.balanceOf(address(this)) +
            totalCollectedRewards() -
            totalBalance();
    }

    function totalCollectedRewards() public view returns (uint256 amount) {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            amount += collectedRewards(_sdgs.at(i));
        }
        return amount;
    }
}
