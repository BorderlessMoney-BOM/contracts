const { expect } = require("chai");
const { ethers } = require("hardhat");

function toUSDC(amount) {
  return ethers.utils.parseUnits(amount, 6);
}

async function skipHours(hours) {
  await ethers.provider.send("evm_increaseTime", [hours * 60 * 60]);
  await ethers.provider.send("evm_mine");
}

describe("Aave USDC Strategy", function () {
  let strategy;
  let usdc;
  let sdg1;
  let sdg2;
  let fakePool;

  beforeEach(async function () {
    [_, sdg1, sdg2] = await ethers.getSigners();
    const USDC = await ethers.getContractFactory("USDC");
    const AaveUsdcStrategy = await ethers.getContractFactory(
      "AaveUSDCStrategy"
    );
    usdc = await USDC.deploy();

    const FakePool = await ethers.getContractFactory("FakePool");
    fakePool = await FakePool.deploy(usdc.address);
    strategy = await AaveUsdcStrategy.deploy(
      usdc.address,
      fakePool.address,
      fakePool.address
    );

    await strategy.grantRole(await strategy.VAULT_ROLE(), sdg1.address);
    await strategy.grantRole(await strategy.VAULT_ROLE(), sdg2.address);

    await usdc.mint(sdg1.address, toUSDC("100000"));
    await usdc.mint(sdg2.address, toUSDC("100000"));
    await usdc.connect(sdg1).approve(strategy.address, toUSDC("100000"));
    await usdc.connect(sdg2).approve(strategy.address, toUSDC("100000"));
  });

  it("Should deposits increases sdgs balances", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("100"));
    await strategy.connect(sdg1).delegate(toUSDC("200"));
    await strategy.connect(sdg2).delegate(toUSDC("300"));
    await strategy.connect(sdg2).delegate(toUSDC("300"));
    expect(await strategy.balanceOf(sdg1.address)).to.equal(toUSDC("300"));
    expect(await strategy.balanceOf(sdg2.address)).to.equal(toUSDC("600"));
  });

  it("Should reward amounts be computed correctly between sdgs", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));
    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("1000")
    );
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("2000")
    );
    expect(await strategy.totalRewards()).to.equal(
      ethers.BigNumber.from("3000")
    );
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("2000")
    );
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("2000")
    );
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods after a withdraw", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    await strategy.connect(sdg2).undelegate(toUSDC("1"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("3002")
    );

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("4004")
    );
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods after collect rewards", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    await strategy.connect(sdg2).collectRewards(ethers.BigNumber.from("2000"));

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("2001")
    );
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("0")
    );

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("2000")
    );
  });
});
