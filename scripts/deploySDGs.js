const hre = require("hardhat");

const allSdgs = [
  {
    id: 1,
    name: "No Poverty",
  },
  {
    id: 2,
    name: "Zero Hunger",
  },
  {
    id: 3,
    name: "Good Health and Well-Being",
  },
  {
    id: 4,
    name: "Quality Education",
  },
  {
    id: 5,
    name: "Gender Equality",
  },
  {
    id: 6,
    name: "Clean Water and Sanitation",
  },
  {
    id: 7,
    name: "Affordable and Clean Energy",
  },
  {
    id: 8,
    name: "Decent Work and Economic Growth",
  },
  {
    id: 9,
    name: "Industry, Innovation and Infrastructure",
  },
  {
    id: 10,
    name: "Reduced Inequalities",
  },
  {
    id: 11,
    name: "Sustainable Cities and Communities",
  },
  {
    id: 12,
    name: "Responsible Consumption &amp; Production",
  },
  {
    id: 13,
    name: "Climate Action",
  },
  {
    id: 14,
    name: "Life Below Water",
  },
  {
    id: 15,
    name: "Life on Land",
  },
  {
    id: 16,
    name: "Peace, Justice and Strong Institutions",
  },
  {
    id: 17,
    name: "Partnerships for the Goals",
  },
];

async function main() {
  const usdc = "0x9aa7fEc87CA69695Dd1f879567CcF49F3ba417E2";
  const feeReceiver = "0x1F09759ca7bE92eAf23660f00Afa363Cc5d32822";
  const borderlessNftAddress = "0xb630c023bBFfdF3A4632b5d0837F218f1135bBb6";
  const aaveStrategy = "0x44B6ffB3e2b3e6FEBc7CF08E9418301d88Ff67AB";

  const BorderlessNFT = await hre.ethers.getContractFactory("BorderlessNFT");
  const AaveUsdcStrategy = await hre.ethers.getContractFactory(
    "AaveUSDCStrategy"
  );
  const borderlessNft = await BorderlessNFT.deploy();
  const SDG = await hre.ethers.getContractFactory("SDGStaking");

  const sdgs = [];

  const aaveUsdcStrategy = await AaveUsdcStrategy.attach(aaveStrategy);

  for (let sdg of allSdgs) {
    console.log(`Deploying SDG ${sdg.id} - ${sdg.name}`);
    const sdgStaking = await SDG.deploy(
      borderlessNftAddress,
      usdc,
      feeReceiver,
      `${sdg.id} - ${sdg.name}`
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

    sdgs.push(sdgStaking.address);
    console.log(
      `npx hardhat verify --network mumbai ${sdgStaking.address} ${borderlessNftAddress} ${usdc} ${feeReceiver} "${sdg.id} - ${sdg.name}"`
    );
  }

  for (let i = 0; i < sdgs.length; i++) {
    console.log(
      `npx hardhat verify --network mumbai ${sdgs[i]} ${borderlessNftAddress} ${usdc} ${feeReceiver} "${allSdgs[i].id} - ${allSdgs[i].name}"`
    );
  }

  console.log(JSON.stringify({ sdgs }));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
