//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IStaking.sol";
import "./IBorderlessNFT.sol";
import "./strategy/IStrategy.sol";

import "hardhat/console.sol";

contract SDGStaking is IStaking, Ownable {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 _usdc;
    IBorderlessNFT _nft;
    Counters.Counter _epochCounter;
    EnumerableSet.AddressSet _activeStrategies;

    mapping(uint256 => StoredBalance) _epochIdToStoredBalances;
    mapping(uint256 => StakeInfo) _stakeIdToStakeInfo;
    mapping(StakeStatus => EnumerableSet.UintSet) _stakeStatusToStakeIds;

    event Stake(uint256 stakeId, uint256 amount, uint256 stakePeriod);

    constructor(address nft, address usdc) {
        _nft = IBorderlessNFT(nft);
        _usdc = IERC20(usdc);
    }

    function stake(uint256 amount) external override {
        if (amount == 0) {
            revert InvalidAmount(amount, 1 ether);
        }

        uint256 stakeId = _nft.totalSupply();
        _nft.safeMint(msg.sender, address(this));

        bool sent = _usdc.transferFrom(msg.sender, address(this), amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                msg.sender,
                address(this),
                amount
            );
        }

        uint256 epoch = _epochCounter.current();
        _epochIdToStoredBalances[epoch].nextEpochBalance += amount;

        _stakeIdToStakeInfo[stakeId] = StakeInfo({
            amount: amount,
            createdAt: block.timestamp,
            stakePeriod: 10,
            status: StakeStatus.UNDELEGATED,
            strategies: new address[](0),
            shares: new uint256[](0),
            epoch: epoch + 1
        });

        _stakeStatusToStakeIds[StakeStatus.UNDELEGATED].add(stakeId);

        emit Stake(stakeId, amount, 10);
    }

    function stakeInfoByStakeId(uint256 stakeId)
        public
        view
        override
        returns (StakeInfo memory)
    {
        return _stakeIdToStakeInfo[stakeId];
    }

    function storedBalanceInCurrentEpoch()
        public
        view
        returns (StoredBalance memory)
    {
        uint256 epoch = _epochCounter.current();
        return storedBalanceByEpochId(epoch);
    }

    function storedBalanceByEpochId(uint256 epochId)
        public
        view
        override
        returns (StoredBalance memory)
    {
        return _epochIdToStoredBalances[epochId];
    }

    function stakeBalanceByStatus(StakeStatus status)
        public
        view
        override
        returns (uint256 balance)
    {
        uint256 total = _stakeStatusToStakeIds[status].length();

        for (uint256 i = 0; i < total; i++) {
            StakeInfo memory stakeInfo = _stakeIdToStakeInfo[
                _stakeStatusToStakeIds[status].at(i)
            ];
            balance += stakeInfo.amount;
        }
    }

    function stakesByStatus(StakeStatus status)
        public
        view
        override
        returns (uint256[] memory stakeIds)
    {
        uint256 total = _stakeStatusToStakeIds[status].length();
        stakeIds = new uint256[](total);

        for (uint256 i = 0; i < total; i++) {
            stakeIds[i] = _stakeStatusToStakeIds[status].at(i);
        }

        return stakeIds;
    }

    function delegateAll(address[] memory strategies, uint256[] memory shares)
        external
        override
        onlyOwner
    {
        if (strategies.length == 0) {
            revert EmptyStrategies();
        }
        if (strategies.length != shares.length) {
            revert StrategiesAndSharesLengthsNotEqual(
                strategies.length,
                shares.length
            );
        }

        uint256 totalShares;
        for (uint256 i = 0; i < strategies.length; i++) {
            totalShares += shares[i];
        }
        if (totalShares != 100) {
            revert InvalidSharesSum(totalShares, 100);
        }

        uint256 totalUndelegated = _stakeStatusToStakeIds[
            StakeStatus.UNDELEGATED
        ].length();
        uint256 undelegatedAmount = 0;
        for (uint256 i = totalUndelegated; i > 0; i--) {
            uint256 stakeId = _stakeStatusToStakeIds[StakeStatus.UNDELEGATED]
                .at(i - 1);
            StakeInfo memory stakeInfo = _stakeIdToStakeInfo[stakeId];
            undelegatedAmount += stakeInfo.amount;
            _stakeIdToStakeInfo[stakeId].status = StakeStatus.DELEGATED;
            _stakeIdToStakeInfo[stakeId].strategies = strategies;
            _stakeIdToStakeInfo[stakeId].shares = shares;
            _stakeStatusToStakeIds[StakeStatus.UNDELEGATED].remove(i - 1);
            _stakeStatusToStakeIds[StakeStatus.DELEGATED].add(stakeId);
        }

        if (undelegatedAmount == 0) {
            revert NothingToDelegate();
        }

        for (uint256 i = 0; i < strategies.length; i++) {
            if (!_activeStrategies.contains(strategies[i])) {
                revert InvalidStrategy(strategies[i]);
            }
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 amount = (undelegatedAmount * shares[i]) / 100;
            _usdc.approve(address(strategy), amount);
            strategy.delegate(address(strategy), amount);
        }
    }

    function endEpoch() external override {
        if (_usdc.balanceOf(address(this)) != 0) {
            revert USDCBalanceIsNotZero(_usdc.balanceOf(address(this)));
        }

        _epochCounter.increment();
        uint256 currentEpoch = _epochCounter.current();
        _epochIdToStoredBalances[currentEpoch] = StoredBalance({
            currentEpoch: currentEpoch,
            currentEpochBalance: _epochIdToStoredBalances[currentEpoch - 1]
                .nextEpochBalance,
            nextEpochBalance: 0
        });
    }

    function addStrategy(address strategy) external override onlyOwner {
        _activeStrategies.add(strategy);
    }

    function removeStrategy(address strategy) external override onlyOwner {
        _activeStrategies.remove(strategy);
    }

    function activeStrategies()
        public
        view
        returns (address[] memory strategies)
    {
        uint256 total = _activeStrategies.length();
        strategies = new address[](total);

        for (uint256 i = 0; i < total; i++) {
            strategies[i] = _activeStrategies.at(i);
        }

        return strategies;
    }

    function totalRewards() external view override returns (uint256 amount) {
        uint256 totalStrategies = _activeStrategies.length();
        for (uint256 i = 0; i < totalStrategies; i++) {
            IStrategy strategy = IStrategy(_activeStrategies.at(i));
            amount += strategy.totalRewards(address(this));
        }

        return amount;
    }

    function collectedRewards()
        external
        view
        override
        returns (uint256 amount)
    {
        uint256 totalStrategies = _activeStrategies.length();
        for (uint256 i = 0; i < totalStrategies; i++) {
            IStrategy strategy = IStrategy(_activeStrategies.at(i));
            amount += strategy.collectedRewards(address(this));
        }

        return amount;
    }

    function collectRewards() external override onlyOwner {
        uint256 totalStrategies = _activeStrategies.length();
        uint256 amount;
        for (uint256 i = 0; i < totalStrategies; i++) {
            IStrategy strategy = IStrategy(_activeStrategies.at(i));
            uint256 availableRewards = strategy.totalRewards(address(this)) -
                strategy.collectedRewards(address(this));
            amount += availableRewards;
            strategy.collectRewards(address(this), availableRewards);
        }

        _usdc.transfer(msg.sender, amount);
    }
}
