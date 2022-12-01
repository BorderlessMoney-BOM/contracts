// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "./IStrategy.sol";

interface IUnipilotVault {
    /// @notice Deposits tokens in proportion to the Unipilot's current holdings & mints them
    /// `Unipilot`s LP token.
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param recipient Recipient of shares
    /// @return lpShares Number of shares minted
    /// @return amount0 Amount of token0 deposited in vault
    /// @return amount1 Amount of token1 deposited in vault
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    )
        external
        payable
        returns (
            uint256 lpShares,
            uint256 amount0,
            uint256 amount1
        );

    /// @notice Withdraws the desired shares from the vault with accumulated user fees and transfers to recipient.
    /// @param recipient Recipient of tokens
    /// @param refundAsETH whether to recieve in WETH or ETH (only valid for WETH/ALT pairs)
    /// @return amount0 Amount of token0 sent to recipient
    /// @return amount1 Amount of token1 sent to recipient
    function withdraw(
        uint256 liquidity,
        address recipient,
        bool refundAsETH
    ) external returns (uint256 amount0, uint256 amount1);

    function balanceOf(address account) external view returns (uint256);
}

interface SwapRouter is IV3SwapRouter {
    function WETH9() external pure returns (address);

    function refundETH() external;
}

contract UnipilotLPStrategy is IStrategy, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IUnipilotVault _vault;
    EnumerableSet.AddressSet _sdgs;
    SwapRouter _uniswapRouter;

    bool _paused;

    uint256 _supply;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _shares;

    constructor(
        address usdc,
        address vault,
        address uniswapRouter,
        address pool
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _usdc = IERC20(usdc);
        _vault = IUnipilotVault(vault);
        _uniswapRouter = SwapRouter(uniswapRouter);
    }

    function _vaultBalance() internal view returns (uint256) {
        return _vault.balanceOf(address(this));
    }

    function _totalSupply() internal view returns (uint256) {
        return _supply;
    }

    function _getPricePerFullShare() internal view returns (uint256) {
        return
            _totalSupply() == 0
                ? 1e18
                : (_vaultBalance() * 1e18) / _totalSupply();
    }

    function getMaticLatestPrice() public view returns (uint256) {
        return 90349550;
        // (, int256 price, , , ) = _priceFeed.latestRoundData();
        // return uint256(price);
    }

    function lpSharesPrice() external view returns (uint256) {}

    function _usdcToMatic(uint256 amount) internal {
        _usdc.approve(address(_uniswapRouter), amount);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: address(_usdc),
                tokenOut: _uniswapRouter.WETH9(),
                fee: 3000,
                recipient: address(this),
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        _uniswapRouter.exactInputSingle(params);

        IWETH(_uniswapRouter.WETH9()).withdraw(
            IERC20(_uniswapRouter.WETH9()).balanceOf(address(this))
        );
    }

    function _maticToUsdc(uint256 amount) internal {
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: _uniswapRouter.WETH9(),
                tokenOut: address(_usdc),
                fee: 3000,
                recipient: address(this),
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        _uniswapRouter.exactInputSingle{value: amount}(params);
        _uniswapRouter.refundETH();
    }

    function _supplyPool(uint256 amount) internal returns (uint256 lpShares) {
        _usdc.transferFrom(msg.sender, address(this), amount);

        uint256 previousMaticBalance = address(this).balance;
        _usdcToMatic(amount / 2);
        uint256 maticAmount = address(this).balance - previousMaticBalance;

        _usdc.approve(address(_vault), amount);
        (lpShares, , ) = _vault.deposit{value: maticAmount}(
            maticAmount,
            amount / 2,
            address(this)
        );

        return lpShares;
    }

    function _redeemPool(uint256 amount) internal returns (uint256) {
        uint256 balanceBefore = _usdc.balanceOf(address(this));

        uint256 shares = (amount * 1e18) / _vault.getPricePerFullShare();

        uint256 lastSgPoolUsdcBalance = _sgPoolUsdc.balanceOf(address(this));
        _vault.withdraw(shares);
        uint256 sgPoolUsdcBalance = _sgPoolUsdc.balanceOf(address(this)) -
            lastSgPoolUsdcBalance;
        _swapLpForUsdc(sgPoolUsdcBalance);

        return _usdc.balanceOf(address(this)) - balanceBefore;
    }

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        _sdgs.add(msg.sender);

        uint256 _before = _vaultBalance();

        amount = _supplyPool(amount);

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
        uint256 shares = (amount * _totalSupply()) / _vaultBalance();
        if (shares > _shares[msg.sender]) {
            shares = _shares[msg.sender];
            amount = (shares * _vaultBalance()) / _totalSupply();
        }

        _shares[msg.sender] -= shares;
        _supply -= shares;

        amount = _redeemPool(amount);

        bool sent = _usdc.transfer(msg.sender, amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                amount
            );
        }
        _delegatedAmount[msg.sender] -= amount;

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

        uint256 shares = (amount * _totalSupply()) / _vaultBalance();

        _shares[msg.sender] -= shares;
        _supply -= shares;

        amount = _redeemPool(amount);

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

    function sharesOf(address sdg) public view returns (uint256) {
        return _shares[sdg];
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
        return _vaultBalance() + totalCollectedRewards() - totalBalance();
    }

    function totalCollectedRewards() public view returns (uint256 amount) {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            amount += collectedRewards(_sdgs.at(i));
        }
        return amount;
    }
}
