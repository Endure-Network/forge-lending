// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Script} from "@forge-std/Script.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {MockXVS} from "@protocol/endure/MockXVS.sol";

contract DeployWithOptionals is Script {
    function run() external {
        require(block.chainid == 31337, "DeployWithOptionals: chainId != anvil");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(pk);

        bool enableXVS = vm.envOr("ENABLE_XVS", false);
        bool enableVAI = vm.envOr("ENABLE_VAI", false);
        bool enableLiquidator = vm.envOr("ENABLE_LIQUIDATOR", false);
        bool enablePrime = vm.envOr("ENABLE_PRIME", false);

        vm.startBroadcast(pk);

        EndureDeployHelper helper = new EndureDeployHelper();
        EndureDeployHelper.Addresses memory addr = helper.deployAll();

        address xvs;
        if (enableXVS) {
            xvs = _enableXVSRewards(helper, addr, deployer);
        }

        EndureDeployHelper.VAIAddresses memory vaiAddresses;
        if (enableVAI) {
            vaiAddresses = _enableVAI(helper, addr, deployer);
        }

        EndureDeployHelper.LiquidatorAddresses memory liquidatorAddresses;
        if (enableLiquidator) {
            require(enableVAI, "DeployWithOptionals: ENABLE_LIQUIDATOR requires ENABLE_VAI");
            liquidatorAddresses = _enableLiquidator(helper, addr);
        }

        require(!enablePrime, "DeployWithOptionals: ENABLE_PRIME not implemented yet");

        vm.stopBroadcast();

        _writeAddresses(addr, xvs, vaiAddresses, liquidatorAddresses, enableVAI, enableLiquidator, enablePrime);
    }

    function _enableXVSRewards(
        EndureDeployHelper helper,
        EndureDeployHelper.Addresses memory addr,
        address deployer
    ) internal returns (address xvsAddress) {
        MockXVS xvs = new MockXVS();

        uint256 fundingAmount = vm.envOr("XVS_FUNDING_AMOUNT", uint256(1_000e18));
        uint256 supplySpeed = vm.envOr("XVS_VWTAO_SUPPLY_SPEED", uint256(1e18));
        uint256 borrowSpeed = vm.envOr("XVS_VWTAO_BORROW_SPEED", uint256(0));

        xvs.mint(deployer, fundingAmount);
        xvs.approve(address(helper), fundingAmount);

        address[] memory markets = new address[](1);
        markets[0] = addr.vWTAO;
        uint256[] memory supplySpeeds = new uint256[](1);
        supplySpeeds[0] = supplySpeed;
        uint256[] memory borrowSpeeds = new uint256[](1);
        borrowSpeeds[0] = borrowSpeed;

        helper.enableVenusRewards(address(xvs), markets, supplySpeeds, borrowSpeeds, fundingAmount);
        return address(xvs);
    }

    function _enableVAI(
        EndureDeployHelper helper,
        EndureDeployHelper.Addresses memory addr,
        address deployer
    ) internal returns (EndureDeployHelper.VAIAddresses memory vaiAddresses) {
        EndureDeployHelper.VAIConfig memory config = EndureDeployHelper.VAIConfig({
            vaiMintRate: vm.envOr("VAI_MINT_RATE", uint256(5_000)),
            mintCap: vm.envOr("VAI_MINT_CAP", uint256(1_000_000e18)),
            receiver: vm.envOr("VAI_RECEIVER", deployer),
            treasuryGuardian: vm.envOr("VAI_TREASURY_GUARDIAN", deployer),
            treasuryAddress: vm.envOr("VAI_TREASURY_ADDRESS", deployer),
            treasuryPercent: vm.envOr("VAI_TREASURY_PERCENT", uint256(0)),
            baseRateMantissa: vm.envOr("VAI_BASE_RATE", uint256(0)),
            floatRateMantissa: vm.envOr("VAI_FLOAT_RATE", uint256(0))
        });

        bytes memory vaiCreationCode = abi.encodePacked(
            vm.getCode("../contracts/out/VAI.sol/VAI.json"),
            abi.encode(block.chainid)
        );
        return helper.deployVAIOptional(addr, config, vaiCreationCode);
    }

    function _enableLiquidator(
        EndureDeployHelper helper,
        EndureDeployHelper.Addresses memory addr
    ) internal returns (EndureDeployHelper.LiquidatorAddresses memory liquidatorAddresses) {
        EndureDeployHelper.LiquidatorConfig memory config = EndureDeployHelper.LiquidatorConfig({
            treasuryPercentMantissa: vm.envOr("LIQUIDATOR_TREASURY_PERCENT", uint256(0.05e18)),
            minLiquidatableVAI: vm.envOr("LIQUIDATOR_MIN_LIQUIDATABLE_VAI", uint256(0)),
            pendingRedeemChunkLength: vm.envOr("LIQUIDATOR_PENDING_REDEEM_CHUNK_LENGTH", uint256(10))
        });

        return helper.deployLiquidatorOptional(addr, config);
    }

    function _writeAddresses(
        EndureDeployHelper.Addresses memory addr,
        address xvs,
        EndureDeployHelper.VAIAddresses memory vaiAddresses,
        EndureDeployHelper.LiquidatorAddresses memory liquidatorAddresses,
        bool enableVAI,
        bool enableLiquidator,
        bool enablePrime
    ) internal {
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
        vm.serializeAddress(json, "mockAlpha64", addr.mockAlpha64);

        vm.serializeAddress(json, "xvs", xvs);
        vm.serializeAddress(json, "vai", vaiAddresses.vai);
        vm.serializeAddress(json, "vaiController", vaiAddresses.vaiController);
        vm.serializeAddress(json, "vaiControllerImplementation", vaiAddresses.vaiControllerImplementation);
        vm.serializeAddress(json, "liquidator", liquidatorAddresses.liquidator);
        vm.serializeAddress(json, "liquidatorImplementation", liquidatorAddresses.liquidatorImplementation);
        vm.serializeAddress(json, "protocolShareReserve", liquidatorAddresses.protocolShareReserve);
        vm.serializeAddress(json, "prime", address(0));
        vm.serializeAddress(json, "primeLiquidityProvider", address(0));
        vm.serializeBool(json, "enableVAI", enableVAI);
        vm.serializeBool(json, "enableLiquidator", enableLiquidator);
        string memory finalJson = vm.serializeBool(json, "enablePrime", enablePrime);

        vm.writeJson(finalJson, string.concat(vm.projectRoot(), "/addresses-optionals.json"));
    }
}
