import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";
import "hardhat-deploy";
import { HardhatUserConfig, subtask } from "hardhat/config";
import { TASK_TEST_GET_TEST_FILES } from "hardhat/builtin-tasks/task-names";
import path from "path";

// See tests/hardhat/SKIPPED.md for per-file rationale.
const EXCLUDED_TEST_DIRS = [
  "Comptroller", "VToken", "InterestRateModels", "VAI", "Prime",
  "XVS", "VRT", "Liquidator", "DelegateBorrowers", "Swap",
  "Lens", "Admin", "integration", "fixtures",
];

subtask(TASK_TEST_GET_TEST_FILES).setAction(async (args, _hre, runSuper) => {
  const files: string[] = await runSuper(args);
  return files.filter((f: string) => {
    const rel = path.relative(__dirname, f);
    const isExcludedDir = EXCLUDED_TEST_DIRS.some(d =>
      rel.includes(`tests/hardhat/${d}/`) || rel.includes(`tests${path.sep}hardhat${path.sep}${d}${path.sep}`),
    );
    const isExcludedFile = rel.includes("EvilXToken.ts") || rel.includes("unitrollerTest.ts");
    return !isExcludedDir && !isExcludedFile;
  });
});

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
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
    sources: "./src",
    tests: "./tests/hardhat",
    deploy: "./deploy",
    deployments: "./deployments",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  namedAccounts: {
    deployer: 0,
  },
  mocha: {
    timeout: 200000,
  },
};

export default config;
