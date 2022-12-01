const hre = require("hardhat");
const currentContracts = require("../current.json");

async function main() {
  const Strategy = await hre.ethers.getContractFactory("BeefyUSDCLPStrategy");
  const SDG = await hre.ethers.getContractFactory("SDGStaking");

  const strategy = await Strategy.attach(
    currentContracts.strategies.beefy_usdc_lp
  );

  for (let sdgAddress of currentContracts.sdgs) {
    console.log("Linking strategy to SDG", sdgAddress);

    // const sdg = await SDG.attach(sdgAddress);
    // await sdg.addStrategy(strategy.address);
    await strategy.grantRole(await strategy.VAULT_ROLE(), sdgAddress);

    console.log("Linked");
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
