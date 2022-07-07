// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

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

interface IStrategy {
    event Delegate(uint256 amount);
    event Withdraw(uint256 amount);
    event CollectRewards(uint256 amount);

    /// @dev Transfer USDC tokens to the strategy contract.
    /// @param amount The amount of USDC tokens to transfer.
    function delegate(uint256 amount) external;

    /// @dev Withdraw USDC tokens from the strategy contract.
    /// @param amount The amount of USDC tokens to withdraw.
    function undelegate(uint256 amount) external;

    /// @dev Compute the total rewards for the given SDG.
    /// @return The total rewards for the given SDG.
    function totalRewards() external view returns (uint256);

    /// @dev Compute the total rewards collected by the given SDG.
    /// @return The total rewards collected by the given SDG.
    function collectedRewards()
        external
        view
        returns (uint256);

    /// @dev Collect rewards for the given SDG.
    function collectRewards(uint256 amount) external;

    /// @dev Compute the total balance without rewards of the SDG on the strategy.
    /// @return The total balance without rewards of the SDG on the strategy.
    function balance() external view returns (uint256);
}
