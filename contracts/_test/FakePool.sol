// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./USDC.sol";
import "../strategy/IStrategy.sol";

import "hardhat/console.sol";

error NotEnoughBalance(uint256 amount, uint256 balance);

contract FakePool is IERC20 {
    USDC _usdc;

    mapping(address => uint256) _balances;
    mapping(address => uint256) _mintDate;
    uint256 _totalSupply;

    constructor(address usdc) {
        _usdc = USDC(usdc);
    }

    function name() public pure returns (string memory) {
        return "FakeUSDCPool";
    }

    function symbol() public pure returns (string memory) {
        return "fakeUSDC";
    }

    function decimals() public pure returns (uint8) {
        return 6;
    }

    function supply(
        address token,
        uint256 amount,
        address controller,
        uint16 referer
    ) public {
        _usdc.transferFrom(msg.sender, address(this), amount);
        _mint(controller, amount);
        _totalSupply += amount;

        token;
        referer;
    }

    function withdraw(
        address token,
        uint256 amount,
        address receiver
    ) public returns (uint256) {
        token;
        if (_balances[msg.sender] < amount) {
            revert NotEnoughBalance(amount, _balances[msg.sender]);
        }

        _burn(msg.sender, amount);
        if (amount > _usdc.balanceOf(address(this))) {
            uint missingAmount = amount - _usdc.balanceOf(address(this));
            _usdc.mint(address(this), missingAmount);
        }
        _usdc.transfer(receiver, amount);

        return amount;
    }

    function _mint(address to, uint256 amount) internal {
        _balances[to] = balanceOf(to);
        _balances[to] += amount;
        _mintDate[to] = block.timestamp;

        // console.log("[Fake Pool] Minting", amount, "to", to);
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        _balances[from] = balanceOf(from);
        _balances[from] -= amount;
        _mintDate[from] = block.timestamp;

        // console.log("[Fake Pool] Burning", amount, "from", from);
        emit Transfer(from, address(0), amount);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 diffInSeconds = block.timestamp - _mintDate[account];
        return
            _balances[account] +
            (_balances[account] * diffInSeconds / 3600) /
            1000;
    }

    function transfer(address to, uint256 amount)
        external
        override
        returns (bool)
    {
        _balances[msg.sender] = balanceOf(msg.sender);
        _mintDate[msg.sender] = block.timestamp;
        _balances[msg.sender] -= amount;
        _balances[to] = balanceOf(to);
        _mintDate[to] = block.timestamp;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        pure
        override
        returns (uint256)
    {
        owner;
        spender;
        return 10000 ether;
    }

    function approve(address spender, uint256 amount)
        external
        pure
        override
        returns (bool)
    {
        spender;
        amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        if (amount > balanceOf(from)) {
            revert NotEnoughBalance(amount, balanceOf(from));
        }

        _balances[from] = balanceOf(from);
        _mintDate[from] = block.timestamp;
        _balances[from] -= amount;
        _balances[to] = balanceOf(to);
        _mintDate[to] = block.timestamp;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }
}
