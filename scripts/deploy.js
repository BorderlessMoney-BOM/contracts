const hre = require("hardhat");

async function main() {
  const usdc = "0x9aa7fEc87CA69695Dd1f879567CcF49F3ba417E2";
  const aPolUsdc = "0xCdc2854e97798AfDC74BC420BD5060e022D14607";
  const aavePool = "0x6c9fb0d5bd9429eb9cd96b85b81d872281771e6b";

  const BorderlessNFT = await hre.ethers.getContractFactory("BorderlessNFT");
  const AaveUsdcStrategy = await hre.ethers.getContractFactory("AaveUSDCStrategy");
  const borderlessNft = await BorderlessNFT.deploy();
  const SDG = await hre.ethers.getContractFactory("SDGStaking");
  const sdgStaking = await SDG.deploy(borderlessNft.address, usdc);

  const aaveUsdcStrategy = await AaveUsdcStrategy.deploy(
    usdc,
    aPolUsdc,
    aavePool
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

  console.log("Borderless NFT deployed to:", borderlessNft.address);
  console.log("Aave USDC strategy deployed to:", aaveUsdcStrategy.address);
  console.log("SDG Staking deployed to:", sdgStaking.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
