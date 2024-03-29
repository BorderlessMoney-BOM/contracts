//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IBorderlessNFT {
    function safeMint(address to, address sdgOperator) external returns (uint256 stakeId);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

    function operatorByTokenId(uint256 tokenId) external view returns (address);

    function endEpoch() external;

    function burn(uint256 tokenId) external;
}
