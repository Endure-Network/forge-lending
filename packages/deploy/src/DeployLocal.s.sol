// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Script} from "@forge-std/Script.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";

contract DeployLocal is Script {
    function run() external {
        require(block.chainid == 31337, "DeployLocal: chainId != anvil");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        vm.startBroadcast(pk);

        EndureDeployHelper helper = new EndureDeployHelper();
        EndureDeployHelper.Addresses memory addr = helper.deployAll();

        vm.stopBroadcast();

        string memory json = "addresses";
        vm.serializeAddress(json, "unitroller", addr.unitroller);
        vm.serializeAddress(json, "comptrollerLens", addr.comptrollerLens);
        vm.serializeAddress(json, "accessControlManager", addr.accessControlManager);
        vm.serializeAddress(json, "resilientOracle", addr.resilientOracle);
        vm.serializeAddress(json, "marketFacet", addr.marketFacet);
        vm.serializeAddress(json, "policyFacet", addr.policyFacet);
        vm.serializeAddress(json, "setterFacet", addr.setterFacet);
        vm.serializeAddress(json, "rewardFacet", addr.rewardFacet);
        vm.serializeAddress(json, "vWTAO", addr.vWTAO);
        vm.serializeAddress(json, "vAlpha30", addr.vAlpha30);
        vm.serializeAddress(json, "vAlpha64", addr.vAlpha64);
        vm.serializeAddress(json, "irmWTAO", addr.irmWTAO);
        vm.serializeAddress(json, "irmAlpha", addr.irmAlpha);
        vm.serializeAddress(json, "wtao", addr.wtao);
        vm.serializeAddress(json, "mockAlpha30", addr.mockAlpha30);
        string memory finalJson = vm.serializeAddress(json, "mockAlpha64", addr.mockAlpha64);

        vm.writeJson(finalJson, string.concat(vm.projectRoot(), "/addresses.json"));
    }
}
