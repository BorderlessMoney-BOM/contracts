const hre = require("hardhat");

async function main() {
  const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  const vault = "0x2F4BBA9fC4F77F16829F84181eB7C8b50F639F95"; // https://polygonscan.com/address/0x2F4BBA9fC4F77F16829F84181eB7C8b50F639F95#code
  const sgRouter = "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd"; // https://polygonscan.com/address/0x45A01E4e04F14f7A4a6702c74187c5F6222033cd#code
  const pool = "0x1205f31718499dBf1fCa446663B532Ef87481fe1"; // https://polygonscan.com/address/0x1205f31718499dBf1fCa446663B532Ef87481fe1#code

  const BeefyUSDCLPStrategy = await hre.ethers.getContractFactory(
    "BeefyUSDCLPStrategy"
  );
  const beefyUSDCLPStrategy = await BeefyUSDCLPStrategy.deploy(
    usdc,
    vault,
    sgRouter,
    pool
  );

  console.log(
    "Beefy USDC LP strategy deployed to:",
    beefyUSDCLPStrategy.address,
    `npx hardhat verify ${beefyUSDCLPStrategy.address} --network matic ${usdc} ${vault} ${sgRouter} ${pool}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
