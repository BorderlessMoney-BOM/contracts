const { expect } = require("chai");
const { ethers } = require("hardhat");

function toUSDC(amount) {
  return ethers.utils.parseUnits(amount, 6);
}

async function skipHours(hours) {
  await ethers.provider.send("evm_increaseTime", [hours * 60 * 60]);
  await ethers.provider.send("evm_mine");
}

describe("Beefy USDC LP Strategy", function () {
  let strategy;
  let usdc;
  let sdg1;
  let sdg2;
  let fakePool, fakeVault, fakeRouter;

  beforeEach(async function () {
    [_, sdg1, sdg2] = await ethers.getSigners();
    const USDC = await ethers.getContractFactory("USDC");
    const BeefyUSDCLP = await ethers.getContractFactory("BeefyUSDCLPStrategy");
    usdc = await USDC.deploy();

    const FakePool = await ethers.getContractFactory("FakeStargatePool");
    fakePool = await FakePool.deploy(usdc.address);
    const FakeVault = await ethers.getContractFactory("FakeBeefyVault");
    fakeVault = await FakeVault.deploy(fakePool.address);
    const FakeRouter = await ethers.getContractFactory("FakeStargateRouter");
    fakeRouter = await FakeRouter.deploy(fakePool.address, usdc.address);

    strategy = await BeefyUSDCLP.deploy(
      usdc.address,
      fakeVault.address,
      fakeRouter.address,
      fakePool.address
    );

    await strategy.grantRole(await strategy.VAULT_ROLE(), sdg1.address);
    await strategy.grantRole(await strategy.VAULT_ROLE(), sdg2.address);

    await usdc.mint(sdg1.address, toUSDC("100000000"));
    await usdc.mint(sdg2.address, toUSDC("100000000"));
    await usdc.connect(sdg1).approve(strategy.address, toUSDC("100000000"));
    await usdc.connect(sdg2).approve(strategy.address, toUSDC("100000000"));
  });

  it("Should deposits increases sdgs balances", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));
    await strategy.connect(sdg1).delegate(toUSDC("2"));
    await strategy.connect(sdg2).delegate(toUSDC("3"));
    await strategy.connect(sdg2).delegate(toUSDC("3"));
    expect(await strategy.balanceOf(sdg1.address)).to.equal("3000000");
    expect(await strategy.balanceOf(sdg2.address)).to.equal("6000000");
  });

  it("Should reward amounts be computed correctly between sdgs", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));
    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("10")
    );
    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      ethers.BigNumber.from("20"),
    ]);
    expect(await strategy.totalRewards()).deep.oneOf([
      ethers.BigNumber.from("30"),
    ]);
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("20")
    );
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("19")
    );
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods after a withdraw", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    await strategy.connect(sdg2).undelegate(toUSDC("1"));

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      ethers.BigNumber.from("29"),
      ethers.BigNumber.from("30"),
    ]);

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("39")
    );
  });

  it("Should reward amounts be computed correctly between sdgs when delegate in different periods after collect rewards", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    await strategy
      .connect(sdg2)
      .collectRewards(await strategy.availableRewards(sdg2.address));

    expect(await strategy.availableRewards(sdg1.address)).deep.oneOf([
      ethers.BigNumber.from("20"),
    ]);
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("1")
    );

    await skipHours(1);

    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      ethers.BigNumber.from("21"),
    ]);
  });

  it("Should rewards be withdrawn successfully", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    await strategy
      .connect(sdg1)
      .collectRewards(await strategy.availableRewards(sdg1.address));

    await strategy
      .connect(sdg2)
      .collectRewards(await strategy.availableRewards(sdg2.address));

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("1")
    );
    expect(await strategy.availableRewards(sdg2.address)).to.equal(
      ethers.BigNumber.from("0")
    );

    await strategy.connect(sdg1).undelegate(toUSDC("1"));

    await strategy.connect(sdg2).undelegate(toUSDC("1"));

    expect(await strategy.balanceOf(sdg1.address)).to.equal(
      ethers.BigNumber.from("1")
    );
    expect(await strategy.balanceOf(sdg2.address)).to.equal(
      ethers.BigNumber.from("1000000")
    );

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("0")
    );

    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      ethers.BigNumber.from("0"),
      ethers.BigNumber.from("1"),
    ]);

    expect(await strategy.availableRewards(sdg1.address)).to.equal(
      ethers.BigNumber.from("0")
    );
  });

  it("Should collect all available rewards", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    const sdg1AvailableRewards = await strategy.availableRewards(sdg1.address);
    const sdg2AvailableRewards = await strategy.availableRewards(sdg2.address);

    await strategy.connect(sdg1).collectRewards(sdg1AvailableRewards.div(2));
    await strategy.connect(sdg2).collectRewards(sdg2AvailableRewards.div(2));

    await strategy
      .connect(sdg1)
      .undelegate(await strategy.balanceOf(sdg1.address));

    expect(await strategy.availableRewards(sdg1.address)).deep.oneOf([
      sdg1AvailableRewards.div(2).sub(1),
      sdg1AvailableRewards.div(2),
      sdg1AvailableRewards.div(2).add(1),
    ]);

    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      sdg1AvailableRewards.div(2).sub(1),
      sdg1AvailableRewards.div(2),
      sdg1AvailableRewards.div(2).add(1),
      sdg1AvailableRewards.div(2).add(2),
    ]);

    expect(await strategy.balanceOf(sdg1.address)).to.equal(
      ethers.BigNumber.from("1")
    );
    expect(await strategy.balanceOf(sdg2.address)).to.equal("1999999");
  });

  it("Should collect all available rewards", async function () {
    await strategy.connect(sdg1).delegate(toUSDC("1"));

    await skipHours(1);

    await strategy.connect(sdg2).delegate(toUSDC("2"));

    await skipHours(1);

    const sdg1AvailableRewards = await strategy.availableRewards(sdg1.address);
    const sdg2AvailableRewards = await strategy.availableRewards(sdg2.address);

    await strategy.connect(sdg1).collectRewards(sdg1AvailableRewards.div(2));
    await strategy.connect(sdg2).collectRewards(sdg2AvailableRewards.div(2));

    await strategy
      .connect(sdg1)
      .undelegate((await strategy.balanceOf(sdg1.address)).mul(2));

    expect(await strategy.availableRewards(sdg1.address)).deep.oneOf([
      sdg1AvailableRewards.div(2).sub(1),
      sdg1AvailableRewards.div(2),
      sdg1AvailableRewards.div(2).add(1),
      sdg1AvailableRewards.div(2).add(2),
    ]);

    expect(await strategy.availableRewards(sdg2.address)).deep.oneOf([
      sdg1AvailableRewards.div(2).sub(1),
      sdg1AvailableRewards.div(2),
      sdg1AvailableRewards.div(2).add(1),
      sdg1AvailableRewards.div(2).add(2),
    ]);

    expect(await strategy.balanceOf(sdg1.address)).to.equal(
      ethers.BigNumber.from("1")
    );
    expect(await strategy.balanceOf(sdg2.address)).to.equal("1999999");
  });
});
