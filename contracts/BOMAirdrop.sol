// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract BOMAirdrop is EIP712, Ownable {
    event Claimed(address indexed account, uint256 amount);

    IERC20 immutable BOM;
    address _signerAddress;

    mapping(address => uint256) _accountToClaimedBOM;

    constructor(address bom, address signer) EIP712("BOM Airdrop", "1.0.0") {
        BOM = IERC20(bom);
        setSignerAddress(signer);
    }

    function claim(uint256 maxAmount, bytes calldata signature) external {
        require(
            recoverAddress(msg.sender, maxAmount, signature) == _signerAddress,
            "invalid signature"
        );
        uint256 claimed = _accountToClaimedBOM[msg.sender];
        uint256 availableAmount = maxAmount - claimed;

        _accountToClaimedBOM[msg.sender] += availableAmount;

        if (availableAmount > 0) {
            BOM.transfer(msg.sender, availableAmount);

            emit Claimed(msg.sender, availableAmount);
        }
    }

    function _hash(address account, uint256 maxAmount)
        internal
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("AIRDROP(uint256 maxAmount,address account)"),
                        maxAmount,
                        account
                    )
                )
            );
    }

    function claimedBOM(address account) external view returns (uint256) {
        return _accountToClaimedBOM[account];
    }

    function recoverAddress(
        address account,
        uint256 maxAmount,
        bytes calldata signature
    ) public view returns (address) {
        return ECDSA.recover(_hash(account, maxAmount), signature);
    }

    function setSignerAddress(address signerAddress) public onlyOwner {
        _signerAddress = signerAddress;
    }

    function withdrawBOM() external onlyOwner {
        BOM.transfer(msg.sender, BOM.balanceOf(address(this)));
    }
}
