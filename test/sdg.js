const { expect } = require("chai");
const { ethers } = require("hardhat");
const { smockit } = require("@eth-optimism/smock");
const customError = require("./utils/customError");

async function skipHours(hours) {
  await ethers.provider.send("evm_increaseTime", [hours * 60 * 60]);
  await ethers.provider.send("evm_mine");
}

describe("SDG", function () {
  let sdgStaking;
  let usdc;
  let borderlessNft;
  let aaveUsdcStrategy;
  let addr1;
  let addr2;
  let feeReceiver;

  beforeEach(async function () {
    [_, addr1, addr2, feeReceiver] = await ethers.getSigners();
    const BorderlessNFT = await ethers.getContractFactory("BorderlessNFT");
    const USDC = await ethers.getContractFactory("USDC");
    const AaveUsdcStrategy = await ethers.getContractFactory(
      "AaveUSDCStrategy"
    );
    borderlessNft = await BorderlessNFT.deploy();
    usdc = await USDC.deploy();
    const SDG = await ethers.getContractFactory("SDGStaking");
    sdgStaking = await SDG.deploy(
      borderlessNft.address,
      usdc.address,
      feeReceiver.address,
      "SDG 1"
    );

    aaveUsdcStrategy = await AaveUsdcStrategy.deploy(
      usdc.address,
      usdc.address,
      usdc.address
    );

    await borderlessNft.grantRole(
      await borderlessNft.MINTER_ROLE(),
      sdgStaking.address
    );

    await borderlessNft.grantRole(
      await borderlessNft.BURNER_ROLE(),
      sdgStaking.address
    );

    await usdc.mint(addr1.address, ethers.utils.parseEther("1000"));

    await usdc
      .connect(addr1)
      .approve(sdgStaking.address, ethers.utils.parseEther("1000"));

    await aaveUsdcStrategy.grantRole(
      await aaveUsdcStrategy.VAULT_ROLE(),
      sdgStaking.address
    );
  });

  it("Should stake emit Stake event", async function () {
    await expect(
      await sdgStaking
        .connect(addr1)
        .stake(ethers.utils.parseEther("1"), 0, addr1.address)
    ).to.emit(sdgStaking, "Stake");
  });

  it("Should stake mint an NFT", async function () {
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1"), 0, addr1.address);

    expect(await borderlessNft.balanceOf(addr1.address)).to.equal(1);
  });

  it("Should stake save token balance", async function () {
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1"), 0, addr1.address);

    const tokenId = await borderlessNft.tokenOfOwnerByIndex(addr1.address, 0);
    const stakeInfo = await sdgStaking.stakeInfoByStakeId(tokenId);

    expect(stakeInfo.amount).equal(ethers.utils.parseEther("1"));
  });

  it("Should stake increase next epoch balance", async function () {
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1"), 0, addr1.address);

    const storedBalanceInCurrentEpoch =
      await sdgStaking.storedBalanceInCurrentEpoch();
    expect(storedBalanceInCurrentEpoch.nextEpochBalance).equal(
      ethers.utils.parseEther("1")
    );
  });

  it("Should stake increase undelegated amount", async function () {
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1"), 0, addr1.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1"), 0, addr1.address);

    expect(await sdgStaking.stakeBalanceByStatus(0)).equal(
      ethers.utils.parseEther("2")
    );
    expect(await sdgStaking.stakeBalanceByStatus(1)).equal(
      ethers.utils.parseEther("0")
    );
  });

  it("Should delegate transfer funds to strategy", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    const strategy2Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking.addStrategy(strategy2Mock.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    await sdgStaking.delegateAll(
      [strategy1Mock.address, strategy2Mock.address],
      [30, 70]
    );

    expect(strategy1Mock.smocked.delegate.calls.length).equal(1);
    expect(strategy2Mock.smocked.delegate.calls.length).equal(1);
    expect(strategy1Mock.smocked.delegate.calls[0].amount).equal(
      ethers.utils.parseEther("3")
    );
    expect(strategy2Mock.smocked.delegate.calls[0].amount).equal(
      ethers.utils.parseEther("7")
    );
  });

  it("Should delegate set stake status to delegated", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    await sdgStaking.delegateAll([strategy1Mock.address], [100]);

    expect((await sdgStaking.stakeInfoByStakeId(0)).status).equal(1);
  });

  it("Should delegate store correct stake statuses", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    expect(await sdgStaking.stakesByStatus(0)).length(2);
    expect(await sdgStaking.stakesByStatus(1)).length(0);

    await sdgStaking.delegateAll([strategy1Mock.address], [100]);

    expect(await sdgStaking.stakesByStatus(0)).length(0);
    expect(await sdgStaking.stakesByStatus(1)).length(2);
  });

  it("Should delegate fails with invalid shares", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);

    await expect(
      sdgStaking.delegateAll([strategy1Mock.address], [30])
    ).revertedWith(customError("InvalidSharesSum", 30, 100));
  });

  it("Should delegate fails if theres theres nothing to delegate", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);

    await expect(
      sdgStaking.delegateAll([strategy1Mock.address], [100])
    ).revertedWith(customError("NothingToDelegate"));
  });

  it("Should delegate fails if use a invalid strategy", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    await expect(
      sdgStaking.delegateAll([strategy1Mock.address], [100])
    ).revertedWith(customError("InvalidStrategy", strategy1Mock.address));
  });

  it("Should delegate fails if use a removed strategy", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking.removeStrategy(strategy1Mock.address);

    await expect(
      sdgStaking.delegateAll([strategy1Mock.address], [100])
    ).revertedWith(customError("InvalidStrategy", strategy1Mock.address));
  });

  it("Should add initiatives successfully", async function () {
    await sdgStaking.addInitiative("Initiative A", addr1.address);
    await sdgStaking.addInitiative("Initiative B", addr2.address);
    const initiatives = await sdgStaking.initiatives();

    expect(initiatives.length).equal(2);
    expect(initiatives[0].id).equal(0);
    expect(initiatives[0].name).equal("Initiative A");
    expect(initiatives[0].controller).equal(addr1.address);
    expect(initiatives[1].id).equal(1);
    expect(initiatives[1].name).equal("Initiative B");
    expect(initiatives[1].controller).equal(addr2.address);
  });

  it("Should remove initiatives successfully", async function () {
    await sdgStaking.addInitiative("Initiative A", addr1.address);
    await sdgStaking.addInitiative("Initiative B", addr2.address);

    await sdgStaking.removeInitiative(0);

    let initiatives = await sdgStaking.initiatives();

    expect(initiatives.length).equal(1);
    expect(initiatives[0].name).equal("Initiative B");
    expect(initiatives[0].controller).equal(addr2.address);

    await sdgStaking.addInitiative("Initiative C", addr1.address);

    initiatives = await sdgStaking.initiatives();

    expect(initiatives.length).equal(2);
    expect(initiatives[0].id).equal(1);
    expect(initiatives[0].name).equal("Initiative B");
    expect(initiatives[0].controller).equal(addr2.address);
    expect(initiatives[1].id).equal(2);
    expect(initiatives[1].name).equal("Initiative C");
    expect(initiatives[1].controller).equal(addr1.address);
  });

  it("Should set initiatives shares successfully", async function () {
    await sdgStaking.addInitiative("Initiative A", addr1.address);
    await sdgStaking.addInitiative("Initiative B", addr2.address);

    await sdgStaking.setInitiativesShares([0, 1], [30, 70]);

    const initiatives = await sdgStaking.initiatives();

    expect(initiatives[0].share).equal(30);
    expect(initiatives[1].share).equal(70);
  });

  it("Should exit collect fee", async function () {
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("1000"), 0, addr1.address);

    await sdgStaking.connect(addr1).exit(0);

    expect(await usdc.balanceOf(addr1.address)).equal(
      ethers.utils.parseEther("970")
    );
  });

  it("Should delegate store correct stake statuses 2", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);

    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);
    await sdgStaking.connect(addr1).exit(0);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);
    await sdgStaking.connect(addr1).exit(1);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);
    await sdgStaking
      .connect(addr1)
      .stake(ethers.utils.parseEther("10"), 0, addr1.address);

    await sdgStaking.addStrategy(strategy1Mock.address);

    expect(await sdgStaking.stakesByStatus(0)).length(2);
    expect(await sdgStaking.stakesByStatus(1)).length(0);

    await sdgStaking.delegateAll([strategy1Mock.address], [100]);

    expect(await sdgStaking.stakesByStatus(0)).length(0);
    expect(await sdgStaking.stakesByStatus(1)).length(2);
  });
});
