//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/// Invalid balance to transfer. Needed `minRequired` but sent `amount`
/// @param sent sent amount.
/// @param minRequired minimum amount to send.
error InvalidAmount(uint256 sent, uint256 minRequired);

/// Strategies cannot be empty
error EmptyStrategies();

/// Strategies and shares lenghts must be equal.
/// @param strategiesLenght lenght of strategies array.
/// @param sharesLenght lenght of shares array.
error StrategiesAndSharesLengthsNotEqual(
    uint256 strategiesLenght,
    uint256 sharesLenght
);

/// Invalid shares sum. Needed `requiredSum` but sent `sum`
/// @param sum sum of shares.
/// @param requiredSum required sum of shares.
error InvalidSharesSum(uint256 sum, uint256 requiredSum);

/// Nothing to delegate
error NothingToDelegate();

/// SDG must not have any USDC left to finish the epoch.
/// @param usdcBalance balance of USDC.
error USDCBalanceIsNotZero(uint256 usdcBalance);

/// Strategy is not active or not exists.
/// @param strategyAddress address of strategy.
error InvalidStrategy(address strategyAddress);

/// Trying to exit a stake thats not owned by the sender.
/// @param sender sender address.
/// @param owner owner address.
/// @param stakeId stake id.
error NotOwnerOfStake(address sender, address owner, uint256 stakeId);

/// Nothing to unstake
error NothingToUnstake();

/// Stake is not delegated
/// @param stakeId stake id.
error StakeIsNotDelegated(uint256 stakeId);

/// Initiatives cannot be empty
error EmptyInitiatives();

/// Initiative ids and shares lenghts must be equal.
/// @param initiativeIdsLength lenght of initiative ids array.
/// @param sharesLenght lenght of shares array.
error InitiativesAndSharesLengthsNotEqual(
    uint256 initiativeIdsLength,
    uint256 sharesLenght
);

/// Initiative is not active
/// @param initiativeId id of initiative.
error InitiativeNotActive(uint256 initiativeId);

/// Initiatives shares neeed to be updated
error InitiativesSharesNeedToBeUpdated();

interface IStaking {
    event Stake(
        uint256 stakeId,
        uint256 amount,
        uint256 stakePeriod,
        address operator
    );
    event Exit(uint256 stakeId, uint256 amount);

    enum StakeStatus {
        UNDELEGATED,
        DELEGATED
    }

    enum StakePeriod {
        THREE_MONTHS,
        SIX_MONTHS,
        ONE_YEAR
    }

    struct StoredBalance {
        uint256 currentEpoch;
        uint256 currentEpochBalance;
        uint256 nextEpochBalance;
    }

    struct StakeInfo {
        StakeStatus status;
        uint256 amount;
        uint256 createdAt;
        StakePeriod stakePeriod;
        uint256 epoch;
        address[] strategies;
        uint256[] shares;
    }

    struct Initiative {
        uint256 id;
        string name;
        uint256 share;
        uint256 collectedRewards;
        address controller;
        bool active;
    }

    /// @dev Stake USDC tokens into SDG. Tokens are stored on the SDG until its delegation to strategies.
    /// @param amount of USDC to stake.
    /// @param period of stake.
    /// @param operator operator address.
    function stake(
        uint256 amount,
        StakePeriod period,
        address operator
    ) external;

    /// @dev Unstake USDC tokens from SDG. Tokens are returned to the sender.
    /// @param stakeId of stake to unstake.
    function exit(uint256 stakeId) external;

    function stakesByStatus(StakeStatus status)
        external
        view
        returns (uint256[] memory stakeIds);

    function stakeInfoByStakeId(uint256 stakeId)
        external
        view
        returns (StakeInfo memory);

    function storedBalanceByEpochId(uint256 epochId)
        external
        view
        returns (StoredBalance memory);

    function stakeBalanceByStatus(StakeStatus status)
        external
        view
        returns (uint256 balance);

    function computeFee(
        uint256 initialAmount,
        uint256 stakedAt,
        StakePeriod stakePeriod
    ) external view returns (uint256 finalAmount, uint256 totalFee);

    function feeByStakePeriod(StakePeriod period)
        external
        view
        returns (uint256 fee);

    function setStakePeriodFees(
        uint256 threeMonthsFee,
        uint256 sixMonthsFee,
        uint256 oneYearFee
    ) external;

    function setFeeReceiver(address) external;

    /// @dev Move USDC tokens to strategies by splitting the remaing balance and delegating it to each strategy.
    /// @param strategies of USDC to stake.
    /// @param shares of USDC to stake.
    function delegateAll(address[] memory strategies, uint256[] memory shares)
        external;

    function addStrategy(address strategy) external;

    function removeStrategy(address strategy) external;

    function activeStrategies() external view returns (address[] memory);

    function endEpoch() external;

    function totalRewards() external view returns (uint256);

    function collectedRewards() external view returns (uint256);

    function distributeRewards() external;

    function addInitiative(string memory name, address controller)
        external
        returns (uint256 initiativeId);

    function removeInitiative(uint256 initiativeId) external;

    function setInitiativesShares(
        uint256[] memory initiativeIds,
        uint256[] memory shares
    ) external;

    function initiatives() external view returns (Initiative[] memory);

    /// @dev Current epoch id
    /// @return Current epoch id
    function epoch() external view returns (uint256);
}
