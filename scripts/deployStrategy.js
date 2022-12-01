const hre = require("hardhat");

async function main() {
  const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  const aPolUsdc = "0x625E7708f30cA75bfd92586e17077590C60eb4cD";
  const aavePool = "0x794a61358D6845594F94dc1DB02A252b5b4814aD";

  const AaveUsdcStrategy = await hre.ethers.getContractFactory(
    "AaveUSDCStrategy"
  );
  const aaveUsdcStrategy = await AaveUsdcStrategy.deploy(
    usdc,
    aPolUsdc,
    aavePool
  );

  console.log(
    "Aave USDC strategy deployed to:",
    aaveUsdcStrategy.address,
    `npx hardhat verify ${aaveUsdcStrategy.address} --network matic ${usdc} ${aPolUsdc} ${aavePool}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
