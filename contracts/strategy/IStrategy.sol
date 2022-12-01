// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// Invalid rewards amount. Needed up to `maximumAmount` but sent `amount`
/// @param amount amount collecting
/// @param maximumAmount total rewards available to collect
error InvalidRewardsAmount(uint256 amount, uint256 maximumAmount);

/// Transfer could not be completed.
/// @param token token to transfer.
/// @param from sender address
/// @param to receiver address
/// @param amount amount to transfer.
error TransferFailed(address token, address from, address to, uint256 amount);

/// Undelegate amount must be less or equal than SDG balance.
/// @param sdg sdg address
/// @param amount amount to undelegate
/// @param balance sdg balance
error InvalidUndelegateAmount(address sdg, uint256 amount, uint256 balance);

/// Strategy is paused.
error StrategyPaused();

interface IStrategy {
    event Delegate(address sdg, uint256 amount);
    event Withdraw(address sdg, uint256 amount);
    event CollectRewards(address sdg, uint256 amount);

    /// @dev Transfer USDC tokens to the strategy contract.
    /// @param amount The amount of USDC tokens to transfer.
    function delegate(uint256 amount) external;

    /// @dev Withdraw USDC tokens from the strategy contract.
    /// @param amount The amount of USDC tokens to withdraw.
    /// @return finalAmount The amount of USDC tokens actually withdrawn.
    function undelegate(uint256 amount) external returns (uint256 finalAmount);

    /// @dev Compute the total rewards for the given SDG.
    /// @param sdg The SDG to compute the rewards for.
    /// @return The total rewards for the given SDG.
    function availableRewards(address sdg) external view returns (uint256);

    /// @dev Compute the total rewards collected by the given SDG.
    /// @param sdg The SDG to compute the rewards for.
    /// @return The total rewards collected by the given SDG.
    function collectedRewards(address sdg) external view returns (uint256);

    /// @dev Collect rewards for the given SDG.
    /// @return finalAmount The amount of USDC tokens actually collected.
    function collectRewards(uint256 amount)
        external
        returns (uint256 finalAmount);

    /// @dev Compute the total balance without rewards of the SDG on the strategy.
    /// @param sdg The SDG to compute the balance for.
    /// @return The total balance without rewards of the SDG on the strategy.
    function balanceOf(address sdg) external view returns (uint256);
}
