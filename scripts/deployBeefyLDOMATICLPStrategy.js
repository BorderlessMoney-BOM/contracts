const hre = require("hardhat");

async function main() {
  const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  const vault = "0x831AF875102d934894D1aE29BDf13deA3729cAeA";
  const zap = "0x540A9f99bB730631BF243a34B19fd00BA8CF315C";
  const uniswapRouter = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";

  const BeefyLDOMATICLPVault = await hre.ethers.getContractFactory(
    "BeefyLDOMATICLPStrategy"
  );
  const beefyLDOMATICLPVault = await BeefyLDOMATICLPVault.deploy(
    usdc,
    vault,
    zap,
    uniswapRouter
  );

  const user = "0x38c918Db9dfb6Cfc27F462ce1CD5C56072D0A4f1";
  await beefyLDOMATICLPVault.grantRole(beefyLDOMATICLPVault.VAULT_ROLE(), user);

  console.log(
    "Beefy LDO MATIC strategy deployed to:",
    beefyLDOMATICLPVault.address,
    `npx hardhat verify ${beefyLDOMATICLPVault.address} --network matic ${usdc} ${vault} ${zap} ${uniswapRouter}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
