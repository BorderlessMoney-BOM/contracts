const { expect } = require("chai");
const { ethers } = require("hardhat");
const customError = require("./utils/customError");

function fromUSDC(amount) {
  return ethers.utils.formatUnits(amount, 6);
}

function toUSDC(amount) {
  return ethers.utils.parseUnits(amount, 6);
}

async function skipHours(hours) {
  await ethers.provider.send("evm_increaseTime", [hours * 60 * 60]);
  await ethers.provider.send("evm_mine");
}

describe("End to end", function () {
  let sdgStaking;
  let usdc;
  let borderlessNft;
  let aaveUsdcStrategy;
  let fakePool;
  let addr1;
  let addr2;
  let initiativeA;
  let initiativeB;

  before(async function () {
    [_, addr1, addr2, initiativeA, initiativeB] = await ethers.getSigners();
    const BorderlessNFT = await ethers.getContractFactory("BorderlessNFT");
    const USDC = await ethers.getContractFactory("USDC");
    const AaveUsdcStrategy = await ethers.getContractFactory(
      "AaveUSDCStrategy"
    );
    const FakePool = await ethers.getContractFactory("FakePool");
    borderlessNft = await BorderlessNFT.deploy();
    usdc = await USDC.deploy();
    fakePool = await FakePool.deploy(usdc.address);
    const SDG = await ethers.getContractFactory("SDGStaking");
    sdgStaking = await SDG.deploy(borderlessNft.address, usdc.address);

    aaveUsdcStrategy = await AaveUsdcStrategy.deploy(
      usdc.address,
      fakePool.address,
      fakePool.address
    );

    await borderlessNft.grantRole(
      await borderlessNft.MINTER_ROLE(),
      sdgStaking.address
    );

    await borderlessNft.grantRole(
      await borderlessNft.BURNER_ROLE(),
      sdgStaking.address
    );

    await aaveUsdcStrategy.grantRole(
      await aaveUsdcStrategy.VAULT_ROLE(),
      sdgStaking.address
    );

    await sdgStaking.addStrategy(aaveUsdcStrategy.address);
  });

  it("Should stake successfully", async function () {
    await usdc.mint(addr1.address, toUSDC("10000"));
    await usdc.mint(addr2.address, toUSDC("13000"));
    await usdc.connect(addr1).approve(sdgStaking.address, toUSDC("10000"));
    await usdc.connect(addr2).approve(sdgStaking.address, toUSDC("13000"));
    await expect(sdgStaking.connect(addr1).stake(toUSDC("10000"))).to.emit(
      sdgStaking,
      "Stake"
    );
    await expect(sdgStaking.connect(addr2).stake(toUSDC("13000"))).to.emit(
      sdgStaking,
      "Stake"
    );
  });

  it("Should store stake info", async function () {
    const sdg = sdgStaking.connect(addr1);
    const stake1Info = await sdg.stakeInfoByStakeId(0);
    const stake2Info = await sdg.stakeInfoByStakeId(1);
    expect(stake1Info.amount).equal(toUSDC("10000"));
    expect(stake1Info.status).equal(0);
    expect(stake2Info.amount).equal(toUSDC("13000"));
    expect(stake2Info.status).equal(0);
  });

  it("Should stake mint a NFT to user", async function () {
    expect(await borderlessNft.balanceOf(addr1.address)).equal(1);
    expect(await borderlessNft.balanceOf(addr2.address)).equal(1);
  });

  it("Should controller delegate all to usdc strategy", async function () {
    await sdgStaking.delegateAll([aaveUsdcStrategy.address], [100]);

    const stake1Info = await sdgStaking.stakeInfoByStakeId(0);
    const stake2Info = await sdgStaking.stakeInfoByStakeId(1);

    expect(stake1Info.status).equal(1);
    expect(stake2Info.status).equal(1);
    expect(await fakePool.balanceOf(aaveUsdcStrategy.address)).equal(
      toUSDC("23000")
    );
  });

  it("Should strategy rewards increase", async function () {
    await skipHours(1.1);
    expect(await aaveUsdcStrategy.totalRewards()).equal("25300000");
  });

  it("Should controller distribute rewards successfully", async function () {
    await sdgStaking.addInitiative("Initiative A", initiativeA.address);
    await sdgStaking.addInitiative("Initiative B", initiativeB.address);
    await sdgStaking.setInitiativesShares([0, 1], [50, 50]);

    await sdgStaking.distributeRewards();

    expect(await usdc.balanceOf(initiativeA.address)).equal("12662777");
    expect(await usdc.balanceOf(initiativeB.address)).equal("12662777");
  });

  it("Should exit stake emit exit event", async function () {
    await expect(sdgStaking.connect(addr1).exit(0)).to.emit(sdgStaking, "Exit");
  });

  it("Should exit stake burn NFT", async function () {
    expect(await borderlessNft.balanceOf(addr1.address)).equal(0);
    expect(await borderlessNft.balanceOf(addr2.address)).equal(1);
  });

  it("Should exit stake return USDT amount", async function () {
    expect(await usdc.balanceOf(addr1.address)).equal(toUSDC("10000"));
  });

  it("Should exit stake fails if stake not exists", async function () {
    await expect(sdgStaking.connect(addr1).exit(0)).revertedWith("ERC721");
  });

  it("Should exit stake fails if user is not owner of the stake", async function () {
    await expect(sdgStaking.connect(addr1).exit(1)).revertedWith(
      customError("NotOwnerOfStake", addr1.address, addr2.address, 1)
    );
  });

  it("Should last stake exit successfully", async function () {
    await expect(sdgStaking.connect(addr2).exit(1)).to.emit(sdgStaking, "Exit");
  });

  it("Should exit undelegated stake", async function () {
    await usdc.connect(addr1).approve(sdgStaking.address, toUSDC("10000"));
    await expect(sdgStaking.connect(addr1).stake(toUSDC("10000"))).to.emit(
      sdgStaking,
      "Stake"
    );
  });
});
