// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";

contract DeployLocal is Script, EndureDeployHelper {
    function run() external {
        require(block.chainid == 31337, "DeployLocal: chainId != anvil");

        address deployer = msg.sender;

        EndureRoles.RoleSet memory roles = EndureRoles.RoleSet({
            admin: vm.envOr("ADMIN_EOA", deployer),
            pauseGuardian: vm.envOr("PAUSE_GUARDIAN_EOA", deployer),
            borrowCapGuardian: vm.envOr("BORROW_CAP_GUARDIAN_EOA", deployer),
            supplyCapGuardian: vm.envOr("SUPPLY_CAP_GUARDIAN_EOA", deployer)
        });

        require(
            roles.admin == deployer,
            "Phase 0 broadcast: ADMIN_EOA must equal deployer; multi-signer admin handoff is Phase 4"
        );

        vm.startBroadcast();
        Addresses memory addrs = _deploy();
        vm.stopBroadcast();

        string memory upstreamSha = vm.readFile("../contracts/.upstream-sha");

        vm.writeFile(
            "./broadcast/addresses.json",
            _buildAddressesJson(deployer, upstreamSha, roles, addrs)
        );
    }

    function _buildAddressesJson(
        address deployer,
        string memory upstreamSha,
        EndureRoles.RoleSet memory roles,
        Addresses memory addrs
    ) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '  "chainId": 31337,\n',
                '  "upstreamMoonwellCommit": "', upstreamSha, '",\n',
                '  "deployer": "', vm.toString(deployer), '",\n',
                '  "roles": ', _rolesJson(roles), ',\n',
                '  "contracts": ', _contractsJson(addrs), '\n',
                "}\n"
            )
        );
    }

    function _rolesJson(
        EndureRoles.RoleSet memory roles
    ) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '    "admin": "', vm.toString(roles.admin), '",\n',
                '    "pauseGuardian": "', vm.toString(roles.pauseGuardian), '",\n',
                '    "borrowCapGuardian": "', vm.toString(roles.borrowCapGuardian), '",\n',
                '    "supplyCapGuardian": "', vm.toString(roles.supplyCapGuardian), '"\n',
                "  }"
            )
        );
    }

    function _contractsJson(
        Addresses memory addrs
    ) internal view returns (string memory) {
        string memory chunk1 = string(
            abi.encodePacked(
                "{\n",
                '    "comptrollerProxy": "', vm.toString(addrs.comptrollerProxy), '",\n',
                '    "comptrollerImpl": "', vm.toString(addrs.comptrollerImpl), '",\n',
                '    "mockPriceOracle": "', vm.toString(addrs.mockPriceOracle), '",\n',
                '    "wtao": "', vm.toString(addrs.wtao), '",\n',
                '    "mockAlpha30": "', vm.toString(addrs.mockAlpha30), '",\n',
                '    "mockAlpha64": "', vm.toString(addrs.mockAlpha64), '",\n'
            )
        );

        string memory chunk2 = string(
            abi.encodePacked(
                '    "jumpRateModel_mWTAO": "', vm.toString(addrs.jumpRateModel_mWTAO), '",\n',
                '    "jumpRateModel_mMockAlpha30": "', vm.toString(addrs.jumpRateModel_mMockAlpha30), '",\n',
                '    "jumpRateModel_mMockAlpha64": "', vm.toString(addrs.jumpRateModel_mMockAlpha64), '",\n',
                '    "mErc20Delegate": "', vm.toString(addrs.mErc20Delegate), '",\n'
            )
        );

        string memory chunk3 = string(
            abi.encodePacked(
                '    "mWTAO": "', vm.toString(addrs.mWTAO), '",\n',
                '    "mMockAlpha30": "', vm.toString(addrs.mMockAlpha30), '",\n',
                '    "mMockAlpha64": "', vm.toString(addrs.mMockAlpha64), '"\n',
                "  }"
            )
        );

        return string(
            abi.encodePacked(chunk1, chunk2, chunk3)
        );
    }
}
