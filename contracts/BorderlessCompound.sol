// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStaking.sol";

contract BorderlessCompound is Ownable {
    IERC20 _usdc;

    event Compound(address indexed sdg, uint256 amount);

    constructor(address usdc) {
        _usdc = IERC20(usdc);
    }

    function _stake(address sdg, uint256 amount) internal {
        _usdc.approve(sdg, amount);
        IStaking(sdg).stake(
            amount,
            IStaking.StakePeriod.ONE_YEAR,
            address(this)
        );

        emit Compound(sdg, amount);
    }

    function stakeAll(address[] memory sdgs, uint256[] memory amounts)
        external
        onlyOwner
    {
        require(
            sdgs.length == amounts.length,
            "Amounts and SDGs must be the same length"
        );
        for (uint256 i = 0; i < sdgs.length; i++) {
            _stake(sdgs[i], amounts[i]);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
