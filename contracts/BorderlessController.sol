// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IStaking.sol";

contract BorderlessController is Ownable {
    mapping(uint256 => IStaking) _sdgs;

    constructor(address[] memory sdgs) {
        for (uint256 i = 0; i < 17; i++) {
            _sdgs[i + 1] = IStaking(sdgs[i]);
        }
    }

    function sdg(uint256 id) public view returns (IStaking) {
        return _sdgs[id];
    }

    function delegateAll(address[] memory strategies, uint256[] memory shares)
        external
        onlyOwner
    {
        for (uint256 i = 1; i <= 17; i++) {
            if (
                sdg(i).stakeBalanceByStatus(IStaking.StakeStatus.UNDELEGATED) >
                0
            ) {
                sdg(i).delegateAll(strategies, shares);
            }
        }
    }

    function addStrategy(address strategy) external onlyOwner {
        for (uint256 i = 1; i <= 17; i++) {
            sdg(i).addStrategy(strategy);
        }
    }

    function removeStrategy(address strategy) external onlyOwner {
        for (uint256 i = 1; i <= 17; i++) {
            sdg(i).removeStrategy(strategy);
        }
    }

    function addInitiative(
        string memory name,
        address controller,
        uint256 sdgId
    ) public onlyOwner returns (uint256 initiativeId) {
        return sdg(sdgId).addInitiative(name, controller);
    }

    function removeInitiative(uint256 initiativeId, uint256 sdgId)
        public
        onlyOwner
    {
        sdg(sdgId).removeInitiative(initiativeId);
    }

    function setInitiativesShares(
        uint256[] memory initiativeIds,
        uint256[] memory shares,
        uint256 sdgId
    ) public onlyOwner {
        sdg(sdgId).setInitiativesShares(initiativeIds, shares);
    }

    function addInitiativeBatch(
        string[] memory names,
        address[] memory controllers,
        uint256[] memory sdgIds
    ) public onlyOwner {
        require(
            names.length == controllers.length &&
                controllers.length == sdgIds.length,
            "Invalid input"
        );
        for (uint256 i = 0; i < names.length; i++) {
            addInitiative(names[i], controllers[i], sdgIds[i]);
        }
    }

    function removeInitiativeBatch(
        uint256[] memory initiativeIds,
        uint256[] memory sdgIds
    ) public onlyOwner {
        require(initiativeIds.length == sdgIds.length, "Invalid input");
        for (uint256 i = 0; i < initiativeIds.length; i++) {
            removeInitiative(initiativeIds[i], sdgIds[i]);
        }
    }

    function setInitiativesSharesBatch(
        uint256[][] memory initiativeIds,
        uint256[][] memory shares,
        uint256[] memory sdgIds
    ) public onlyOwner {
        require(
            initiativeIds.length == shares.length &&
                shares.length == sdgIds.length,
            "Invalid input"
        );
        for (uint256 i = 0; i < initiativeIds.length; i++) {
            setInitiativesShares(initiativeIds[i], shares[i], sdgIds[i]);
        }
    }

    function distributeRewards() external onlyOwner {
        for (uint256 i = 1; i <= 17; i++) {
            if (sdg(i).initiatives().length > 0 && sdg(i).totalRewards() > 0) {
                sdg(i).distributeRewards();
            }
        }
    }

    function setStakePeriodFees(
        uint256 threeMonthsFee,
        uint256 sixMonthsFee,
        uint256 oneYearFee
    ) external onlyOwner {
        for (uint256 i = 1; i <= 17; i++) {
            sdg(i).setStakePeriodFees(threeMonthsFee, sixMonthsFee, oneYearFee);
        }
    }

    function setFeeReceiver(address feeReceiver) external onlyOwner {
        for (uint256 i = 1; i <= 17; i++) {
            sdg(i).setFeeReceiver(feeReceiver);
        }
    }

    function stakeBalanceByStatus(IStaking.StakeStatus status)
        external
        view
        returns (uint256 balance)
    {
        for (uint256 i = 1; i <= 17; i++) {
            balance += sdg(i).stakeBalanceByStatus(status);
        }
        return balance;
    }

    function totalRewards() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 1; i <= 17; i++) {
            total += sdg(i).totalRewards();
        }
        return total;
    }

    function collectedRewards() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 1; i <= 17; i++) {
            total += sdg(i).collectedRewards();
        }
        return total;
    }

    function balances() external view returns (uint256[] memory sdgBalances) {
        sdgBalances = new uint256[](17);
        for (uint256 i = 1; i <= 17; i++) {
            sdgBalances[i - 1] =
                sdg(i).stakeBalanceByStatus(IStaking.StakeStatus.UNDELEGATED) +
                sdg(i).stakeBalanceByStatus(IStaking.StakeStatus.DELEGATED);
        }
        return sdgBalances;
    }
}
