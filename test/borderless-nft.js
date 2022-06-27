const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BorderlessNFT", function () {
  it("Should mint and update user balance", async function () {
    const [owner, addr1] = await ethers.getSigners();
    const BorderlessNFT = await ethers.getContractFactory("BorderlessNFT");
    const borderlessNft = await BorderlessNFT.deploy();
    await borderlessNft.deployed();

    const mint = await borderlessNft.safeMint(owner.address, addr1.address);
    await mint.wait();

    expect(await borderlessNft.balanceOf(owner.address)).to.equal(1);
    expect(await borderlessNft.ownerOf(0)).to.equal(owner.address);
  });

  it("Should mint and store operator", async function () {
    const [owner, addr1] = await ethers.getSigners();
    const BorderlessNFT = await ethers.getContractFactory("BorderlessNFT");
    const borderlessNft = await BorderlessNFT.deploy();
    await borderlessNft.deployed();

    const mint = await borderlessNft.safeMint(owner.address, addr1.address);
    await mint.wait();

    expect(await borderlessNft.operatorByTokenId(0)).to.equal(addr1.address);
  });
});
