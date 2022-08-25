const hre = require("hardhat");

async function main() {
  const BOM = await hre.ethers.getContractFactory("BorderlessMoney");
  const bom = await BOM.deploy();

  console.log("BOM deployed to:", bom.address);
  console.log("");

  console.log(`npx hardhat verify --network mumbai ${bom.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
