const { expect } = require("chai");
const { ethers } = require("hardhat");
const { smockit } = require("@eth-optimism/smock");
const customError = require("./utils/customError");

describe("SDG", function () {
  let sdgStaking;
  let usdc;
  let borderlessNft;
  let aaveUsdcStrategy;
  let addr1;

  beforeEach(async function () {
    [_, addr1] = await ethers.getSigners();
    const BorderlessNFT = await ethers.getContractFactory("BorderlessNFT");
    const USDC = await ethers.getContractFactory("USDC");
    const AaveUsdcStrategy = await ethers.getContractFactory(
      "AaveUSDCStrategy"
    );
    borderlessNft = await BorderlessNFT.deploy();
    usdc = await USDC.deploy();
    const SDG = await ethers.getContractFactory("SDGStaking");
    sdgStaking = await SDG.deploy(borderlessNft.address, usdc.address);

    aaveUsdcStrategy = await AaveUsdcStrategy.deploy(
      usdc.address,
      usdc.address,
      usdc.address
    );

    await borderlessNft.grantRole(
      await borderlessNft.MINTER_ROLE(),
      sdgStaking.address
    );

    await usdc.mint(addr1.address, ethers.utils.parseEther("1000"));

    await usdc
      .connect(addr1)
      .approve(sdgStaking.address, ethers.utils.parseEther("100"));

    await aaveUsdcStrategy.grantRole(
      await aaveUsdcStrategy.VAULT_ROLE(),
      sdgStaking.address
    );
  });

  it("Should stake emit Stake event", async function () {
    await expect(
      await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"))
    ).to.emit(sdgStaking, "Stake");
  });

  it("Should stake mint an NFT", async function () {
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"));

    expect(await borderlessNft.balanceOf(addr1.address)).to.equal(1);
  });

  it("Should stake save token balance", async function () {
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"));

    const tokenId = await borderlessNft.tokenOfOwnerByIndex(addr1.address, 0);
    const stakeInfo = await sdgStaking.stakeInfoByStakeId(tokenId);

    expect(stakeInfo.amount).equal(ethers.utils.parseEther("1"));
  });

  it("Should stake increase next epoch balance", async function () {
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"));

    const storedBalanceInCurrentEpoch = await sdgStaking.storedBalanceInCurrentEpoch();
    expect(storedBalanceInCurrentEpoch.nextEpochBalance).equal(
      ethers.utils.parseEther("1")
    );
  });

  it("Should stake increase undelegated amount", async function () {
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"));
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("1"));

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
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));

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
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));

    await sdgStaking.delegateAll(
      [strategy1Mock.address],
      [100]
    );

    expect((await sdgStaking.stakeInfoByStakeId(0)).status).equal(1);
  });

  it("Should delegate store correct stake statuses", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));

    expect(await sdgStaking.stakesByStatus(0)).length(2);
    expect(await sdgStaking.stakesByStatus(1)).length(0);

    await sdgStaking.delegateAll(
      [strategy1Mock.address],
      [100]
    );

    expect(await sdgStaking.stakesByStatus(0)).length(0);
    expect(await sdgStaking.stakesByStatus(1)).length(2);
  });

  it("Should delegate fails with invalid shares", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.addStrategy(strategy1Mock.address);

    await expect(sdgStaking.delegateAll([strategy1Mock.address], [30])).revertedWith(
      customError("InvalidSharesSum", 30, 100)
    );
  });

  it("Should delegate fails if theres theres nothing to delegate", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);

    await expect(sdgStaking.delegateAll([strategy1Mock.address], [100])).revertedWith(
      customError("NothingToDelegate")
    );
  });

  it("Should delegate fails if use a invalid strategy", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));

    await expect(sdgStaking.delegateAll([strategy1Mock.address], [100])).revertedWith(
      customError("InvalidStrategy", strategy1Mock.address)
    );
  });

  it("Should delegate fails if use a removed strategy", async function () {
    const strategy1Mock = await smockit(aaveUsdcStrategy);
    await sdgStaking.connect(addr1).stake(ethers.utils.parseEther("10"));
    
    await sdgStaking.addStrategy(strategy1Mock.address);
    await sdgStaking.removeStrategy(strategy1Mock.address);

    await expect(sdgStaking.delegateAll([strategy1Mock.address], [100])).revertedWith(
      customError("InvalidStrategy", strategy1Mock.address)
    );
  });
});
