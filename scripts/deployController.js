const hre = require("hardhat");
const currentContracts = require("../current.json");

async function main() {
  const SDG = await hre.ethers.getContractFactory("SDGStaking");

  const BorderlessController = await hre.ethers.getContractFactory(
    "BorderlessController"
  );

  // const borderlessController = await BorderlessController.deploy(
  //   currentContracts.sdgs
  // );

  const borderlessController = await BorderlessController.attach(
    "0xB0CaEAEbCB1Db541E92BBa363B616a499A475BBA"
  );

  console.log(
    "Controller deployed to:",
    borderlessController.address,
    `npx hardhat verify ${borderlessController.address} --network matic --constructor-args arguments.js`
  );

  for (let sdgAddress of currentContracts.sdgs.slice(8)) {
    console.log("Adding controller role to SDG", sdgAddress);

    const sdg = await SDG.attach(sdgAddress);
    const tx = await sdg.grantRole(
      await sdg.CONTROLLER_ROLE(),
      borderlessController.address,
      { gasPrice: 284626213421 }
    );
    await tx.wait();

    console.log("Added");
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
