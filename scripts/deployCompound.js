const hre = require("hardhat");

async function main() {
  const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

  const Contract = await hre.ethers.getContractFactory("BorderlessCompound");
  const contract = await Contract.deploy(usdc);

  console.log(
    "Contract deployed to:",
    contract.address,
    `npx hardhat verify ${contract.address} --network matic ${usdc}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
