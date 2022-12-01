// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./FakeStargatePool.sol";
import "hardhat/console.sol";

interface IVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function depositAll() external;

    function balanceOf(address account) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}

contract FakeBeefyVault is IVault {
    uint256 _totalSupply;
    mapping(address => uint256) _balances;

    uint256 startDate;

    FakeStargatePool _sgPool;

    constructor(address poolAddress) {
        _sgPool = FakeStargatePool(poolAddress);
    }

    function balance() public view returns (uint256) {
        return _sgPool.balanceOf(address(this));
    }

    function deposit(uint256 _amount) public override {
        uint256 _pool = balance();
        _sgPool.transferFrom(msg.sender, address(this), _amount);
        uint256 _after = balance();

        _amount = _after - _pool;

        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
            // console.log("shares = _amount");
            startDate = block.timestamp;
        } else {
            shares = (_amount * totalSupply()) / _pool;
        }

        _mint(msg.sender, shares);

        // console.log(
        //     "[Fake Beefy Vault] deposit: %s",
        //     _amount,
        //     balanceOf(msg.sender),
        //     balance()
        // );
    }

    function _mint(address account, uint256 amount) internal {
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function withdraw(uint256 _shares) external override {
        uint256 amount = (_shares * getPricePerFullShare()) / 1e18;

        if (_shares > _balances[msg.sender]) {
            // console.log(
            //     "[Fake Beefy Vault] withdraw: %s",
            //     _shares,
            //     _balances[msg.sender]
            // );
        }
        require(
            _shares <= _balances[msg.sender],
            "[Fake Beefy Vault] Not enough balance"
        );
        _balances[msg.sender] -= _shares;
        _totalSupply -= _shares;
        _sgPool.transfer(msg.sender, amount);

        // console.log(
        //     "[Fake Beefy Vault] withdraw: %s",
        //     amount,
        //     getPricePerFullShare(),
        //     balance()
        // );
    }

    function depositAll() external override {
        deposit(_sgPool.balanceOf(msg.sender));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function getPricePerFullShare() public view override returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (balance() * 1e18) / totalSupply();
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
}
