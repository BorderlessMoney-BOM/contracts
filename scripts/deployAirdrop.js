const hre = require("hardhat");

async function main() {
  const BOM = "0xc59132FBdF8dE8fbE510F568a5D831C991B4fC38";
  const signer = "0x804a9BFdf1438B5F80f8a7C69c0233e8C1d09Ccd";

  const CONTRACT = await hre.ethers.getContractFactory("BOMAirdrop");
  const contract = await CONTRACT.deploy(BOM, signer);

  console.log("Airdrop deployed to:", contract.address);
  console.log("");

  console.log(
    `npx hardhat verify --network matic ${contract.address} ${BOM} ${signer}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
