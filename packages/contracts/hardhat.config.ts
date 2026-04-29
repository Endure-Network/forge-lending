import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.25",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "cancun",
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
  },
  paths: {
    // During staging period (pre-T46): sources at venus-staging/
    // T46 (Commit B1) flips this to "./src" after mass-move
    sources: "./src/venus-staging",
    tests: "./tests/hardhat",
    deploy: "./deploy",
    deployments: "./deployments",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  namedAccounts: {
    deployer: 0,
  },
};

export default config;
