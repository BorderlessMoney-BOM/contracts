//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IBorderlessNFT {
    function safeMint(address to, address sdgOperator) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

    function operatorByTokenId(uint256 tokenId) external view returns (address);

    function endEpoch() external;
}
