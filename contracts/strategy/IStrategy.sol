// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IStrategy {
    event Delegate(address sdgAddress, uint256 amount);
    event Withdraw(address sdgAddress, uint256 amount);
    event CollectRewards(address sdgAddress, uint256 amount);

    /// @dev Transfer USDC tokens to the strategy contract.
    /// @param sdgAddress address of the origin SDG.
    /// @param amount The amount of USDC tokens to transfer.
    function delegate(address sdgAddress, uint256 amount) external;

    /// @dev Withdraw USDC tokens from the strategy contract.
    /// @param sdgAddress address of the origin SDG.
    /// @param amount The amount of USDC tokens to withdraw.
    function withdraw(address sdgAddress, uint256 amount) external;

    /// @dev Compute the total rewards for the given SDG.
    /// @param sdgAddress address of the SDG.
    /// @return The total rewards for the given SDG.
    function totalRewards(address sdgAddress) external view returns (uint256);

    /// @dev Compute the total rewards collected by the given SDG.
    /// @param sdgAddress address of the SDG.
    /// @return The total rewards collected by the given SDG.
    function collectedRewards(address sdgAddress)
        external
        view
        returns (uint256);

    /// @dev Collect rewards for the given SDG.
    /// @param sdgAddress address of the SDG.
    function collectRewards(address sdgAddress, uint256 amount) external;
}
