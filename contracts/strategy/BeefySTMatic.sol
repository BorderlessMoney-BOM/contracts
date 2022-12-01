// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IStrategy.sol";

interface IVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function depositAll() external;

    function balanceOf(address account) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}

interface IBalancerV2 {
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }
}

interface SwapRouter is IV3SwapRouter {
    function WETH9() external pure returns (address);

    function refundETH() external;
}

contract BeefySTMaticStrategy is IStrategy, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 _usdc;
    IERC20 _pool;
    IVault _vault;
    EnumerableSet.AddressSet _sdgs;
    SwapRouter _uniswapRouter;
    IBalancerV2 _balancer;

    ///////////////////
    uint256 fakeMaticPrice = 90349550;
    ///////////////////

    bool _paused;
    uint256 _supply;
    AggregatorV3Interface internal _priceFeed;

    bytes32 constant poolId =
        0x8159462d255c1d24915cb51ec361f700174cd99400000000000000000000075d;

    mapping(address => uint256) _delegatedAmount;
    mapping(address => uint256) _withdrawnAmount;
    mapping(address => uint256) _collectedRewards;
    mapping(address => uint256) _shares;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, msg.sender);
        _usdc = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        _vault = IVault(0xF79BF908d0e6d8E7054375CD80dD33424B1980bf);
        _pool = IERC20(0x8159462d255C1D24915CB51ec361F700174cD994);
        _priceFeed = AggregatorV3Interface(
            0xAB594600376Ec9fD91F8e885dADF0CE036862dE0
        );
        _uniswapRouter = SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        _balancer = IBalancerV2(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    receive() external payable {}

    function getMaticLatestPrice() public view returns (uint256) {
        return fakeMaticPrice;
        // (, int256 price, , , ) = _priceFeed.latestRoundData();
        // return uint256(price);
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

    function _encodeJoinUserData(uint256 amount)
        internal
        pure
        returns (bytes memory userDataEncoded)
    {
        uint256 joinKind = 1;
        uint256[] memory initBalances = new uint256[](2);
        initBalances[0] = amount;
        initBalances[1] = 0;
        userDataEncoded = abi.encode(joinKind, initBalances);

        return userDataEncoded;
    }

    function _encodeExitUserData(uint256 amount)
        internal
        pure
        returns (bytes memory userDataEncoded)
    {
        userDataEncoded = abi.encode(uint256(0), amount, uint256(0));

        return userDataEncoded;
    }

    function _poolBalance() internal view returns (uint256) {
        return
            (_vault.balanceOf(address(this)) * _vault.getPricePerFullShare()) /
            1e18;
    }

    function _poolBalanceInUsdc() internal view returns (uint256) {
        // 10^18 * 10^9 / 10^21 = 10^6
        return (_poolBalance() * getMaticLatestPrice()) / 1e20;
    }

    function _totalSupply() internal view returns (uint256) {
        return _supply;
    }

    function _totalSupplyInUsdc() internal view returns (uint256) {
        return (_totalSupply() * getMaticLatestPrice()) / 1e20;
    }

    function _getPricePerFullShare() internal view returns (uint256) {
        return
            _totalSupply() == 0
                ? 1e18
                : (_poolBalance() * 1e18) / _totalSupply();
    }

    function _getPricePerFullShareInUsdc() internal view returns (uint256) {
        return (_getPricePerFullShare() * getMaticLatestPrice()) / 1e20;
    }

    function _swapUsdcForLp(uint256 amount) internal {
        uint256 initialBalance = address(this).balance;
        _usdcToMatic(amount);
        uint256 maticAmount = address(this).balance - initialBalance;

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[0] = maticAmount;
        maxAmountsIn[1] = 0;
        maxAmountsIn[2] = 0;

        address[] memory assets = new address[](3);
        assets[0] = 0x0000000000000000000000000000000000000000;
        assets[1] = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
        assets[2] = 0x8159462d255C1D24915CB51ec361F700174cD994;

        IBalancerV2.JoinPoolRequest memory request = IBalancerV2
            .JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: _encodeJoinUserData(maticAmount),
                fromInternalBalance: false
            });

        _balancer.joinPool{value: maticAmount}(
            poolId,
            address(this),
            address(this),
            request
        );
    }

    function _swapLpForUsdc(uint256 amount) internal {
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[0] = 100;
        minAmountsOut[1] = 0;
        minAmountsOut[2] = 0;

        address[] memory assets = new address[](3);
        assets[0] = 0x0000000000000000000000000000000000000000;
        assets[1] = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
        assets[2] = 0x8159462d255C1D24915CB51ec361F700174cD994;

        IBalancerV2.ExitPoolRequest memory request = IBalancerV2
            .ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: _encodeExitUserData(amount),
                toInternalBalance: false
            });

        _balancer.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            request
        );
        _maticToUsdc(address(this).balance);
    }

    function _supplyPool(uint256 amount)
        internal
        returns (uint256 usdcAmount, uint256 poolAmount)
    {
        uint256 lastBalance = _poolBalance();
        _usdc.transferFrom(msg.sender, address(this), amount);
        _swapUsdcForLp(amount);

        uint256 balance = _pool.balanceOf(address(this));
        _pool.approve(address(_vault), balance);
        _vault.depositAll();

        return (amount, _poolBalance() - lastBalance);
    }

    function _redeemPool(uint256 amount) internal returns (uint256) {
        uint256 balanceBefore = _usdc.balanceOf(address(this));

        uint256 shares = (amount * 1e18) / _vault.getPricePerFullShare();

        uint256 lastSgPoolUsdcBalance = _pool.balanceOf(address(this));
        _vault.withdraw(shares);
        uint256 sgPoolUsdcBalance = _pool.balanceOf(address(this)) -
            lastSgPoolUsdcBalance;
        _swapLpForUsdc(sgPoolUsdcBalance);

        return _usdc.balanceOf(address(this)) - balanceBefore;
    }

    function delegate(uint256 amount) external onlyRole(VAULT_ROLE) {
        if (isPaused()) revert StrategyPaused();

        _sdgs.add(msg.sender);

        uint256 _before = _poolBalance();
        uint256 baseAmount;
        (amount, baseAmount) = _supplyPool(amount);

        uint256 shares = 0;
        if (_totalSupply() == 0) {
            shares = baseAmount;
        } else {
            shares = (baseAmount * _totalSupply()) / _before;
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
        if (isPaused() || amount == 0) return 0;
        if (amount > balanceOf(msg.sender)) {
            amount = balanceOf(msg.sender);
        }

        uint256 shares = (amount * _totalSupplyInUsdc()) / _poolBalanceInUsdc();
        if (shares > _shares[msg.sender]) {
            shares = _shares[msg.sender];
            amount = (shares * _poolBalanceInUsdc()) / _totalSupplyInUsdc();
        }

        _shares[msg.sender] -= shares;
        _supply -= shares;

        amount = _redeemPool(shares);

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
        if (isPaused()) return collectedRewards(sdg);

        uint256 _before = balanceOf(sdg);
        uint256 _after = (_shares[sdg] * _getPricePerFullShareInUsdc()) / 1e18;

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
        return _poolBalanceInUsdc() + totalCollectedRewards() - totalBalance();
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
