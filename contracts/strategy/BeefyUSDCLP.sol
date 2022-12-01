// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IStrategy.sol";

interface IVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function depositAll() external;

    function balanceOf(address account) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}

interface IStargateRouter {
    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external;

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external;
}

contract BeefyUSDCLPStrategy is IStrategy, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IERC20 _sgPoolUsdc;
    IVault _vault;
    IStargateRouter _sgRouter;
    EnumerableSet.AddressSet _sdgs;

    bool _paused;

    uint256 _supply;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _shares;

    constructor(
        address usdc,
        address vault,
        address sgRouter,
        address pool
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _usdc = IERC20(usdc);
        _vault = IVault(vault);
        _sgRouter = IStargateRouter(sgRouter);
        _sgPoolUsdc = IERC20(pool);
    }

    function _poolBalance() internal view returns (uint256) {
        return
            (_vault.balanceOf(address(this)) * _vault.getPricePerFullShare()) /
            1e18;
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

    function _swapUsdcForLp(uint256 amount) internal {
        _usdc.approve(address(_sgRouter), amount);
        _sgRouter.addLiquidity(1, amount, address(this));
    }

    function _swapLpForUsdc(uint256 amount) internal {
        _sgPoolUsdc.approve(address(_sgRouter), amount);
        _sgRouter.instantRedeemLocal(1, amount, address(this));
    }

    function _supplyPool(uint256 amount) internal returns (uint256) {
        uint256 lastBalance = _poolBalance();
        _usdc.transferFrom(msg.sender, address(this), amount);
        _swapUsdcForLp(amount);

        uint256 balance = _sgPoolUsdc.balanceOf(address(this));
        _sgPoolUsdc.approve(address(_vault), balance);
        _vault.depositAll();

        return _poolBalance() - lastBalance;
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

        uint256 shares = (amount * _totalSupply()) / _poolBalance();

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
}
