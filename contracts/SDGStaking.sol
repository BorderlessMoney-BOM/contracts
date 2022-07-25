//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IStaking.sol";
import "./IBorderlessNFT.sol";
import "./strategy/IStrategy.sol";

import "hardhat/console.sol";

contract SDGStaking is IStaking, AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    IERC20 _usdc;
    IBorderlessNFT _nft;
    Counters.Counter _epochCounter;
    Counters.Counter _initiativesCounter;
    EnumerableSet.AddressSet _activeStrategies;
    EnumerableSet.UintSet _activeInitiatives;
    bool _sharesNeedsUpdate;

    mapping(uint256 => StoredBalance) _epochIdToStoredBalances;
    mapping(uint256 => StakeInfo) _stakeIdToStakeInfo;
    mapping(StakeStatus => EnumerableSet.UintSet) _stakeStatusToStakeIds;
    mapping(uint256 => Initiative) _initiatives;

    constructor(address nft, address usdc) {
        _nft = IBorderlessNFT(nft);
        _usdc = IERC20(usdc);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
    }

    function stake(uint256 amount) external override {
        if (amount == 0) {
            revert InvalidAmount(amount, 1**10 * 6);
        }

        uint256 stakeId = _nft.safeMint(msg.sender, address(this));

        bool sent = _usdc.transferFrom(msg.sender, address(this), amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                msg.sender,
                address(this),
                amount
            );
        }

        uint256 _epoch = _epochCounter.current();
        _epochIdToStoredBalances[_epoch].nextEpochBalance += amount;

        _stakeIdToStakeInfo[stakeId] = StakeInfo({
            amount: amount,
            createdAt: block.timestamp,
            stakePeriod: 10,
            status: StakeStatus.UNDELEGATED,
            strategies: new address[](0),
            shares: new uint256[](0),
            epoch: _epoch + 1
        });

        _stakeStatusToStakeIds[StakeStatus.UNDELEGATED].add(stakeId);

        emit Stake(stakeId, amount, 10);
    }

    function exit(uint256 stakeId) external nonReentrant {
        if (_nft.ownerOf(stakeId) != msg.sender) {
            revert NotOwnerOfStake(msg.sender, _nft.ownerOf(stakeId), stakeId);
        }
        _nft.burn(stakeId);

        /// TODO: check unstake period

        StakeInfo storage stakeInfo = _stakeIdToStakeInfo[stakeId];

        if (stakeInfo.amount == 0) {
            revert NothingToUnstake();
        }

        if (stakeInfo.status == StakeStatus.DELEGATED) {
            _stakeStatusToStakeIds[StakeStatus.DELEGATED].remove(stakeId);
            _undelegate(stakeId);
        } else {
            _stakeStatusToStakeIds[StakeStatus.UNDELEGATED].remove(stakeId);
        }

        bool sent = _usdc.transfer(msg.sender, stakeInfo.amount);
        if (!sent) {
            revert TransferFailed(
                address(_usdc),
                address(this),
                msg.sender,
                stakeInfo.amount
            );
        }

        delete _stakeIdToStakeInfo[stakeId];
        emit Exit(stakeId, stakeInfo.amount);
    }

    function _undelegate(uint256 stakeId) internal {
        StakeInfo storage stakeInfo = _stakeIdToStakeInfo[stakeId];
        if (stakeInfo.status != StakeStatus.DELEGATED) {
            revert StakeIsNotDelegated(stakeId);
        }

        uint256 totalStrategies = stakeInfo.strategies.length;
        for (uint256 i = 0; i < totalStrategies; i++) {
            IStrategy strategy = IStrategy(stakeInfo.strategies[i]);
            uint256 strategyAmount = (stakeInfo.amount * stakeInfo.shares[i]) /
                100;
            strategy.undelegate(strategyAmount);
        }
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
        uint256 _epoch = _epochCounter.current();
        return storedBalanceByEpochId(_epoch);
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
        onlyRole(CONTROLLER_ROLE)
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
            strategy.delegate(amount);
        }
    }

    function endEpoch() external override onlyRole(CONTROLLER_ROLE) {
        if (_sharesNeedsUpdate) {
            revert InitiativesSharesNeedToBeUpdated();
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

    function addStrategy(address strategy)
        external
        override
        onlyRole(CONTROLLER_ROLE)
    {
        _activeStrategies.add(strategy);
    }

    function removeStrategy(address strategy)
        external
        override
        onlyRole(CONTROLLER_ROLE)
    {
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
            amount += strategy.totalRewards();
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
            amount += strategy.collectedRewards();
        }

        return amount;
    }

    function distributeRewards() external override onlyRole(CONTROLLER_ROLE) {
        if (_sharesNeedsUpdate) {
            revert InitiativesSharesNeedToBeUpdated();
        }

        uint256 totalStrategies = _activeStrategies.length();
        uint256 amount;
        for (uint256 i = 0; i < totalStrategies; i++) {
            IStrategy strategy = IStrategy(_activeStrategies.at(i));
            uint256 availableRewards = strategy.totalRewards() -
                strategy.collectedRewards();
            amount += availableRewards;
            strategy.collectRewards(availableRewards);
        }

        uint256 totalInitiatives = _activeInitiatives.length();
        if (totalInitiatives == 0) {
            revert EmptyInitiatives();
        }

        for (uint256 i = 0; i < totalInitiatives; i++) {
            Initiative memory initiative = _initiatives[
                _activeInitiatives.at(i)
            ];
            uint256 initiativeAmount = (amount * initiative.share) / 100;
            bool sent = _usdc.transfer(initiative.controller, initiativeAmount);
            if (!sent) {
                revert TransferFailed(
                    address(_usdc),
                    address(this),
                    initiative.controller,
                    initiativeAmount
                );
            }
        }
    }

    function addInitiative(string memory name, address controller)
        public
        override
        onlyRole(CONTROLLER_ROLE)
        returns (uint256 initiativeId)
    {
        initiativeId = _initiativesCounter.current();
        _initiativesCounter.increment();

        _activeInitiatives.add(initiativeId);
        _sharesNeedsUpdate = true;

        _initiatives[initiativeId] = Initiative({
            id: initiativeId,
            name: name,
            share: 0,
            collectedRewards: 0,
            controller: controller,
            active: true
        });

        return initiativeId;
    }

    function removeInitiative(uint256 initiativeId)
        public
        onlyRole(CONTROLLER_ROLE)
    {
        _activeInitiatives.remove(initiativeId);
        _initiatives[initiativeId].active = false;
        _sharesNeedsUpdate = true;
    }

    function setInitiativesShares(
        uint256[] memory initiativeIds,
        uint256[] memory shares
    ) public override onlyRole(CONTROLLER_ROLE) {
        if (initiativeIds.length == 0) {
            revert EmptyInitiatives();
        }
        if (initiativeIds.length != shares.length) {
            revert InitiativesAndSharesLengthsNotEqual(
                initiativeIds.length,
                shares.length
            );
        }

        _sharesNeedsUpdate = false;

        uint256 totalShares;
        for (uint256 i = 0; i < initiativeIds.length; i++) {
            totalShares += shares[i];
            _initiatives[initiativeIds[i]].share = shares[i];

            if (!_activeInitiatives.contains(initiativeIds[i])) {
                revert InitiativeNotActive(initiativeIds[i]);
            }
        }
        if (totalShares != 100) {
            revert InvalidSharesSum(totalShares, 100);
        }
    }

    function initiatives()
        public
        view
        override
        returns (Initiative[] memory activeInitiatives)
    {
        uint256 total = _activeInitiatives.length();
        activeInitiatives = new Initiative[](total);
        for (uint256 i = 0; i < total; i++) {
            activeInitiatives[i] = _initiatives[_activeInitiatives.at(i)];
        }
        return activeInitiatives;
    }

    function epoch() public view override returns (uint256) {
        return _epochCounter.current();
    }
}
