// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./FakeStargatePool.sol";
import "./USDC.sol";

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

contract FakeStargateRouter is IStargateRouter {
    FakeStargatePool _pool;
    USDC _usdc;

    constructor(address poolAddress, address usdcAddress) {
        _pool = FakeStargatePool(poolAddress);
        _usdc = USDC(usdcAddress);
        _usdc.mint(address(this), 100000000000000000000000000);
    }

    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external override {
        _usdc.transferFrom(msg.sender, address(this), _amountLD);
        _pool.mint(_to, _amountLD);

        _poolId;
    }

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external override {
        _pool.burn(msg.sender, _amountLP);
        _usdc.transfer(_to, _amountLP);

        _srcPoolId;
    }
}
