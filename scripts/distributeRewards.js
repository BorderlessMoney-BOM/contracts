const hre = require("hardhat");
const currentContracts = require("../current.json");

async function main() {
  const SDG = await hre.ethers.getContractFactory("SDGStaking");

  for (let sdgAddress of currentContracts.sdgs) {
    console.log("Distributing SDG", sdgAddress);

    const sdg = await SDG.attach(sdgAddress);

    if ((await sdg.totalRewards()) > 0) {
      try {
        const tx = await sdg.distributeRewards({ gasPrice: 204626213421 });
        console.log(tx);
        await tx.wait();
      } catch (e) {
        console.log("Error distributing rewards", e);
      }
    }

    console.log("Distributed");
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
