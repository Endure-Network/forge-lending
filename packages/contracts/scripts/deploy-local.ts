import fs from "fs";
import path from "path";

import { ethers } from "hardhat";

const ADDRESSES_PATH = path.resolve(__dirname, "..", "..", "deploy", "addresses.json");

async function main() {
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 31337) {
    throw new Error(
      `deploy-local: expected chainId 31337 (hardhat/anvil), got ${network.chainId}. ` +
        `This script only targets the local development chain.`,
    );
  }

  const [deployer] = await ethers.getSigners();
  console.log(`Deployer:                  ${deployer.address}`);
  console.log(`Network:                   ${network.name} (chainId ${network.chainId})`);

  const HelperFactory = await ethers.getContractFactory("EndureDeployHelper");
  const helper = await HelperFactory.deploy();
  await helper.deployed();
  console.log(`EndureDeployHelper:        ${helper.address}`);

  const tx = await helper.deployAll();
  const receipt = await tx.wait();
  console.log(`deployAll() succeeded:     gas ${receipt.gasUsed.toString()}, tx ${receipt.transactionHash}`);

  const a = await helper.getLastDeployment();

  const addresses = {
    accessControlManager: a.accessControlManager,
    comptrollerLens: a.comptrollerLens,
    irmAlpha: a.irmAlpha,
    irmWTAO: a.irmWTAO,
    marketFacet: a.marketFacet,
    mockAlpha30: a.mockAlpha30,
    mockAlpha64: a.mockAlpha64,
    policyFacet: a.policyFacet,
    resilientOracle: a.resilientOracle,
    rewardFacet: a.rewardFacet,
    setterFacet: a.setterFacet,
    unitroller: a.unitroller,
    vAlpha30: a.vAlpha30,
    vAlpha64: a.vAlpha64,
    vWTAO: a.vWTAO,
    wtao: a.wtao,
  };

  for (const [name, addr] of Object.entries(addresses)) {
    if (!addr || addr === ethers.constants.AddressZero) {
      throw new Error(`deploy-local: ${name} is zero/unset after deployAll() - deployment is incomplete`);
    }
  }

  fs.writeFileSync(ADDRESSES_PATH, JSON.stringify(addresses, null, 2) + "\n");
  console.log(`addresses.json written:    ${ADDRESSES_PATH}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
