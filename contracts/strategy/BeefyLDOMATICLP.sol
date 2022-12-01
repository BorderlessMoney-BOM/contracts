// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "./IStrategy.sol";

interface IVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function depositAll() external;

    function balanceOf(address account) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IBeefyUniV2Zap {
    function beefInETH(address beefyVault, uint256 tokenAmountOutMin)
        external
        payable;

    function beefOutAndSwap(
        address beefyVault,
        uint256 withdrawAmount,
        address desiredToken,
        uint256 desiredTokenOutMin
    ) external;
}

interface SwapRouter is IV3SwapRouter {
    function WETH9() external pure returns (address);

    function refundETH() external;
}

contract BeefyLDOMATICLPStrategy is IStrategy, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IVault _vault;
    EnumerableSet.AddressSet _sdgs;
    SwapRouter _uniswapRouter;
    IBeefyUniV2Zap _zap;

    bool _paused;

    uint256 _supply;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _shares;

    constructor(
        address usdc,
        address vault,
        address zap,
        address uniswapRouter
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _usdc = IERC20(usdc);
        _vault = IVault(vault);
        _zap = IBeefyUniV2Zap(zap);
        _uniswapRouter = SwapRouter(uniswapRouter);
    }

    receive() external payable {}

    function _poolBalance() internal view returns (uint256) {
        uint256 pairBalance = (_vault.balanceOf(address(this)) *
            _vault.getPricePerFullShare()) / 1e18;

        return pairBalance;
    }

    function _totalSupply() internal view returns (uint256) {
        return _supply;
    }

    function _getPricePerFullShare() internal view returns (uint256) {
        return
            _totalSupply() == 0
                ? 1e18
                : (_poolBalance() * 1e18) / _totalSupply();
    }

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

    function _supplyPool(uint256 amount) internal returns (uint256) {
        uint256 lastBalance = _poolBalance();

        _usdc.transferFrom(msg.sender, address(this), amount);

        uint256 previousMaticBalance = address(this).balance;
        _usdcToMatic(amount);
        uint256 maticAmount = address(this).balance - previousMaticBalance;

        _zap.beefInETH{value: maticAmount}(address(_vault), 0);

        return _poolBalance() - lastBalance;
    }

    function _redeemPool(uint256 amount) internal returns (uint256) {
        uint256 balanceBefore = _poolBalance();

        uint256 _before = address(this).balance;

        uint256 shares = (amount * 1e18) / _vault.getPricePerFullShare();
        if (shares > _vault.balanceOf(address(this))) {
            shares = _vault.balanceOf(address(this));
        }

        if (shares > 0) {
            _vault.approve(address(_zap), shares);
            _zap.beefOutAndSwap(
                address(_vault),
                shares,
                _uniswapRouter.WETH9(),
                0
            );

            IWETH(_uniswapRouter.WETH9()).withdraw(
                IERC20(_uniswapRouter.WETH9()).balanceOf(address(this))
            );
        }

        uint256 _after = address(this).balance;

        if (_after > _before) {
            _maticToUsdc(_after - _before);
        }

        return balanceBefore - _poolBalance();
    }

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        if (isPaused()) revert StrategyPaused();

        _sdgs.add(msg.sender);

        uint256 _before = _poolBalance();

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
        if (isPaused()) return 0;

        if (amount > balanceOf(msg.sender)) {
            amount = balanceOf(msg.sender);
        }
        uint256 shares = (amount * _totalSupply()) / _poolBalance();
        if (shares > _shares[msg.sender]) {
            shares = _shares[msg.sender];
            amount = (shares * _poolBalance()) / _totalSupply();
        }

        _shares[msg.sender] -= shares;
        _supply -= shares;

        uint256 _before = _usdc.balanceOf(address(this));
        uint256 withdrawnVaultShares = _redeemPool(amount);
        uint256 _after = _usdc.balanceOf(address(this));

        amount = _after - _before;

        bool sent = _usdc.transfer(msg.sender, amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                amount
            );
        }
        _withdrawnAmount[msg.sender] += withdrawnVaultShares;

        emit Withdraw(msg.sender, amount);

        return amount;
    }

    function availableRewards(address sdg)
        public
        view
        returns (uint256 amount)
    {
        if (isPaused()) return collectedRewards(sdg);

        uint256 _before = balanceOf(sdg);
        uint256 _after = (_shares[sdg] * _getPricePerFullShare()) / 1e18;

        if (_before > _after) {
            return collectedRewards(sdg);
        }
        return _after - _before + collectedRewards(sdg);
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
        if (isPaused()) return 0;

        if (
            amount > availableRewards(msg.sender) - collectedRewards(msg.sender)
        ) {
            amount =
                availableRewards(msg.sender) -
                collectedRewards(msg.sender);
        }

        uint256 shares = (amount * _totalSupply()) / _poolBalance();

        _shares[msg.sender] -= shares;
        _supply -= shares;

        uint256 _before = _usdc.balanceOf(address(this));
        uint256 withdrawnVaultShares = _redeemPool(amount);
        uint256 _after = _usdc.balanceOf(address(this));

        amount = _after - _before;

        bool sent = _usdc.transfer(msg.sender, amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                amount
            );
        }

        _collectedRewards[msg.sender] += withdrawnVaultShares;

        emit CollectRewards(msg.sender, amount);

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
        return _poolBalance() + totalCollectedRewards() - totalBalance();
    }

    function totalCollectedRewards() public view returns (uint256 amount) {
        uint256 totalSdgs = _sdgs.length();
        for (uint256 i = 0; i < totalSdgs; i++) {
            amount += collectedRewards(_sdgs.at(i));
        }
        return amount;
    }

    function isPaused() public view returns (bool) {
        return _paused;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _paused = paused;
    }

    function inCaseTokensGetStuck(address _token)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }

    function inCaseMaticGetStuck() external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}
