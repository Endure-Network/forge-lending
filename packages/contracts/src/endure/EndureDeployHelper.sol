// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Unitroller} from "../Comptroller/Unitroller.sol";
import {VToken} from "../Tokens/VTokens/VToken.sol";
import {VBep20Immutable} from "../Tokens/VTokens/VBep20Immutable.sol";
import {ComptrollerInterface} from "../Comptroller/ComptrollerInterface.sol";
import {ComptrollerLensInterface} from "../Comptroller/ComptrollerLensInterface.sol";
import {Diamond} from "../Comptroller/Diamond/Diamond.sol";
import {IDiamondCut} from "../Comptroller/Diamond/interfaces/IDiamondCut.sol";
import {MarketFacet} from "../Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "../Comptroller/Diamond/facets/PolicyFacet.sol";
import {SetterFacet} from "../Comptroller/Diamond/facets/SetterFacet.sol";
import {RewardFacet} from "../Comptroller/Diamond/facets/RewardFacet.sol";
import {ComptrollerLens} from "../Lens/ComptrollerLens.sol";
import {InterestRateModelV8} from "../InterestRateModels/InterestRateModelV8.sol";
import {TwoKinksInterestRateModel} from "../InterestRateModels/TwoKinksInterestRateModel.sol";
import {Liquidator} from "../Liquidator/Liquidator.sol";
import {IPrime} from "../Tokens/Prime/IPrime.sol";
import {Prime} from "../Tokens/Prime/Prime.sol";
import {PrimeLiquidityProvider} from "../Tokens/Prime/PrimeLiquidityProvider.sol";
import {VAIController} from "../Tokens/VAI/VAIController.sol";
import {VAIControllerInterface} from "../Tokens/VAI/VAIControllerInterface.sol";
import {VAIUnitroller} from "../Tokens/VAI/VAIUnitroller.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockResilientOracle} from "./MockResilientOracle.sol";
import {AllowAllAccessControlManager} from "./AllowAllAccessControlManager.sol";
import {EnduRateModelParamsVenus} from "./EnduRateModelParams.sol";
import {LocalProtocolShareReserve} from "./LocalProtocolShareReserve.sol";
import {WTAO} from "./WTAO.sol";
import {MockAlpha30} from "./MockAlpha30.sol";
import {MockAlpha64} from "./MockAlpha64.sol";

contract EndureDeployHelper {
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public deployedUnitroller;

    struct Addresses {
        address unitroller;
        address comptrollerLens;
        address accessControlManager;
        address resilientOracle;
        address marketFacet;
        address policyFacet;
        address setterFacet;
        address rewardFacet;
        address vWTAO;
        address vAlpha30;
        address vAlpha64;
        address irmWTAO;
        address irmAlpha;
        address wtao;
        address mockAlpha30;
        address mockAlpha64;
    }

    struct VAIAddresses {
        address vai;
        address vaiController;
        address vaiControllerImplementation;
    }

    struct VAIConfig {
        uint256 vaiMintRate;
        uint256 mintCap;
        address receiver;
        address treasuryGuardian;
        address treasuryAddress;
        uint256 treasuryPercent;
        uint256 baseRateMantissa;
        uint256 floatRateMantissa;
    }

    struct LiquidatorAddresses {
        address liquidator;
        address liquidatorImplementation;
        address protocolShareReserve;
    }

    struct LiquidatorConfig {
        uint256 treasuryPercentMantissa;
        uint256 minLiquidatableVAI;
        uint256 pendingRedeemChunkLength;
    }

    struct PrimeAddresses {
        address prime;
        address primeImplementation;
        address primeLiquidityProvider;
        address primeLiquidityProviderImplementation;
        address xvsVault;
        address xvsVaultImplementation;
        address xvsStore;
    }

    struct PrimeConfig {
        uint256 blocksPerYear;
        uint256 stakingPeriod;
        uint256 minimumStakedXVS;
        uint256 maximumXVSCap;
        uint256 xvsVaultPoolId;
        uint256 xvsVaultRewardPerBlock;
        uint256 xvsVaultLockPeriod;
        uint128 alphaNumerator;
        uint128 alphaDenominator;
        uint256 loopsLimit;
        uint256 irrevocableLimit;
        uint256 revocableLimit;
        address[] primeMarkets;
        uint256[] supplyMultipliers;
        uint256[] borrowMultipliers;
    }

    struct PrimeBytecode {
        bytes xvsVaultProxyCreationCode;
        bytes xvsVaultCreationCode;
        bytes xvsStoreCreationCode;
    }

    /// @notice Stores the most recent successful deployAll() result so off-chain
    /// callers (e.g. Hardhat scripts that submit deployAll() as a state-changing
    /// transaction) can read the deployed addresses after the transaction is mined.
    /// Foundry callers continue to use the deployAll() return value directly.
    /// Storage is internal because the auto-generated getter for a 16-field
    /// struct exceeds the EVM 16-slot stack limit; getLastDeployment() returns
    /// the struct as a single memory value instead.
    Addresses internal _lastDeployment;

    function getLastDeployment() external view returns (Addresses memory) {
        return _lastDeployment;
    }

    function deployAll() external returns (Addresses memory addrs) {
        AllowAllAccessControlManager accessControlManager = new AllowAllAccessControlManager();
        MockResilientOracle resilientOracle = new MockResilientOracle();
        ComptrollerLens comptrollerLens = new ComptrollerLens();
        Unitroller unitroller = new Unitroller();
        Diamond diamond = new Diamond();
        MarketFacet marketFacet = new MarketFacet();
        PolicyFacet policyFacet = new PolicyFacet();
        SetterFacet setterFacet = new SetterFacet();
        RewardFacet rewardFacet = new RewardFacet();

        require(unitroller._setPendingImplementation(address(diamond)) == 0, "set pending impl");
        diamond._become(unitroller);
        Diamond(payable(address(unitroller))).diamondCut(_buildFacetCut(marketFacet, policyFacet, setterFacet, rewardFacet));

        SetterFacet liveSetter = SetterFacet(address(unitroller));
        MarketFacet liveMarket = MarketFacet(address(unitroller));

        require(
            liveSetter._setComptrollerLens(ComptrollerLensInterface(address(comptrollerLens))) == 0,
            "set comptroller lens"
        );
        require(liveSetter._setPriceOracle(resilientOracle) == 0, "set price oracle");
        require(liveSetter._setAccessControl(address(accessControlManager)) == 0, "set access control");

        addrs.wtao = address(new WTAO());
        addrs.mockAlpha30 = address(new MockAlpha30());
        addrs.mockAlpha64 = address(new MockAlpha64());

        {
            TwoKinksInterestRateModel irmWTAO = new TwoKinksInterestRateModel(
                EnduRateModelParamsVenus.WTAO_BASE_RATE_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_KINK1,
                EnduRateModelParamsVenus.WTAO_MULTIPLIER_2_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_BASE_RATE_2_PER_YEAR,
                EnduRateModelParamsVenus.WTAO_KINK2,
                EnduRateModelParamsVenus.WTAO_JUMP_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.BLOCKS_PER_YEAR
            );
            addrs.irmWTAO = address(irmWTAO);
        }

        {
            TwoKinksInterestRateModel irmAlpha = new TwoKinksInterestRateModel(
                EnduRateModelParamsVenus.ALPHA_BASE_RATE_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_KINK1,
                EnduRateModelParamsVenus.ALPHA_MULTIPLIER_2_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_BASE_RATE_2_PER_YEAR,
                EnduRateModelParamsVenus.ALPHA_KINK2,
                EnduRateModelParamsVenus.ALPHA_JUMP_MULTIPLIER_PER_YEAR,
                EnduRateModelParamsVenus.BLOCKS_PER_YEAR
            );
            addrs.irmAlpha = address(irmAlpha);
        }

        {
            VBep20Immutable vWTAO = new VBep20Immutable(
                addrs.wtao,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmWTAO),
                1e18,
                "Endure WTAO",
                "vWTAO",
                8,
                payable(address(this))
            );
            addrs.vWTAO = address(vWTAO);
            require(liveMarket._supportMarket(VToken(address(vWTAO))) == 0, "support vWTAO");
            resilientOracle.setUnderlyingPrice(address(vWTAO), 1e18);
        }

        {
            VBep20Immutable vAlpha30 = new VBep20Immutable(
                addrs.mockAlpha30,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmAlpha),
                1e18,
                "Endure Alpha30",
                "vALPHA30",
                8,
                payable(address(this))
            );
            addrs.vAlpha30 = address(vAlpha30);
            require(liveMarket._supportMarket(VToken(address(vAlpha30))) == 0, "support vAlpha30");
            resilientOracle.setUnderlyingPrice(address(vAlpha30), 1e18);
        }

        {
            VBep20Immutable vAlpha64 = new VBep20Immutable(
                addrs.mockAlpha64,
                ComptrollerInterface(address(unitroller)),
                InterestRateModelV8(addrs.irmAlpha),
                1e18,
                "Endure Alpha64",
                "vALPHA64",
                8,
                payable(address(this))
            );
            addrs.vAlpha64 = address(vAlpha64);
            require(liveMarket._supportMarket(VToken(address(vAlpha64))) == 0, "support vAlpha64");
            resilientOracle.setUnderlyingPrice(address(vAlpha64), 1e18);
        }

        _configurePhase3(liveSetter, addrs);
        _seedAndBurn(addrs.wtao, addrs.vWTAO, 1e18);
        _seedAndBurn(addrs.mockAlpha30, addrs.vAlpha30, 1e18);
        _seedAndBurn(addrs.mockAlpha64, addrs.vAlpha64, 1e18);

        deployedUnitroller = address(unitroller);

        addrs.unitroller = address(unitroller);
        addrs.comptrollerLens = address(comptrollerLens);
        addrs.accessControlManager = address(accessControlManager);
        addrs.resilientOracle = address(resilientOracle);
        addrs.marketFacet = address(marketFacet);
        addrs.policyFacet = address(policyFacet);
        addrs.setterFacet = address(setterFacet);
        addrs.rewardFacet = address(rewardFacet);

        // Mirror the result into storage for off-chain transactional consumers.
        // Foundry's vm.startBroadcast() callers continue to use the return value;
        // Hardhat scripts submitting deployAll() as a tx read lastDeployment()
        // via the auto-generated getter after the tx is mined.
        // Assignment is delegated to a helper to keep deployAll()'s stack
        // depth under the EVM 16-slot limit (the Addresses struct has 16 fields).
        _persistDeployment(addrs);
    }

    function _persistDeployment(Addresses memory addrs) internal {
        _lastDeployment = addrs;
    }

    function enableVenusRewards(
        address xvsToken,
        address[] calldata vTokens,
        uint256[] calldata supplySpeeds,
        uint256[] calldata borrowSpeeds,
        uint256 fundingAmount
    ) external {
        require(deployedUnitroller != address(0), "not deployed");

        SetterFacet(address(deployedUnitroller))._setXVSToken(xvsToken);

        if (fundingAmount != 0) {
            require(
                IERC20(xvsToken).transferFrom(msg.sender, address(deployedUnitroller), fundingAmount),
                "xvs transfer failed"
            );
        }

        uint256 len = vTokens.length;
        VToken[] memory rewardMarkets = new VToken[](len);
        for (uint256 i; i < len; i++) {
            rewardMarkets[i] = VToken(vTokens[i]);
        }

        PolicyFacet(address(deployedUnitroller))._setVenusSpeeds(rewardMarkets, supplySpeeds, borrowSpeeds);
    }

    function deployVAIOptional(
        Addresses memory addrs,
        VAIConfig memory config,
        bytes memory vaiCreationCode
    ) external returns (VAIAddresses memory vaiAddrs) {
        require(deployedUnitroller != address(0), "not deployed");
        require(addrs.unitroller == deployedUnitroller, "wrong unitroller");
        require(vaiCreationCode.length != 0, "empty VAI code");
        require(config.receiver != address(0), "receiver zero");
        require(config.treasuryGuardian != address(0), "treasury guardian zero");
        require(config.treasuryAddress != address(0), "treasury zero");

        address vai = _deployVAI(vaiCreationCode);
        VAIUnitroller vaiUnitroller = new VAIUnitroller();
        VAIController vaiControllerImplementation = new VAIController();

        require(
            vaiUnitroller._setPendingImplementation(address(vaiControllerImplementation)) == 0,
            "set VAI implementation"
        );
        vaiControllerImplementation._become(vaiUnitroller);

        VAIController liveVAIController = VAIController(address(vaiUnitroller));
        liveVAIController.initialize();
        _relyVAI(vai, address(vaiUnitroller));
        liveVAIController.setVAIToken(vai);
        liveVAIController.setAccessControl(addrs.accessControlManager);
        require(liveVAIController._setComptroller(ComptrollerInterface(addrs.unitroller)) == 0, "set VAI comptroller");

        SetterFacet liveSetter = SetterFacet(addrs.unitroller);
        require(
            liveSetter._setVAIController(VAIControllerInterface(address(vaiUnitroller))) == 0,
            "set comptroller VAI controller"
        );
        require(liveSetter._setVAIMintRate(config.vaiMintRate) == 0, "set VAI mint rate");

        liveVAIController.setReceiver(config.receiver);
        require(
            liveVAIController._setTreasuryData(
                config.treasuryGuardian,
                config.treasuryAddress,
                config.treasuryPercent
            ) == 0,
            "set VAI treasury"
        );
        liveVAIController.setBaseRate(config.baseRateMantissa);
        liveVAIController.setFloatRate(config.floatRateMantissa);
        liveVAIController.setMintCap(config.mintCap);
        MockResilientOracle(addrs.resilientOracle).setUnderlyingPrice(vai, 1e18);

        vaiAddrs.vai = vai;
        vaiAddrs.vaiController = address(vaiUnitroller);
        vaiAddrs.vaiControllerImplementation = address(vaiControllerImplementation);
    }

    function deployLiquidatorOptional(
        Addresses memory addrs,
        LiquidatorConfig memory config
    ) external returns (LiquidatorAddresses memory liquidatorAddrs) {
        require(deployedUnitroller != address(0), "not deployed");
        require(addrs.unitroller == deployedUnitroller, "wrong unitroller");
        require(_readAddress(addrs.unitroller, "vaiController()") != address(0), "VAI required");
        require(config.pendingRedeemChunkLength != 0, "chunk length zero");

        LocalProtocolShareReserve protocolShareReserve = new LocalProtocolShareReserve();
        Liquidator liquidatorImplementation = new Liquidator(
            addrs.unitroller,
            payable(address(0x000000000000000000000000000000000000bEEF)),
            addrs.wtao
        );
        bytes memory initData = abi.encodeCall(
            Liquidator.initialize,
            (config.treasuryPercentMantissa, addrs.accessControlManager, address(protocolShareReserve))
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(liquidatorImplementation),
            address(0x000000000000000000000000000000000000AD01),
            initData
        );

        Liquidator liveLiquidator = Liquidator(payable(address(proxy)));
        liveLiquidator.setMinLiquidatableVAI(config.minLiquidatableVAI);
        liveLiquidator.setPendingRedeemChunkLength(config.pendingRedeemChunkLength);
        SetterFacet(addrs.unitroller)._setLiquidatorContract(address(proxy));

        liquidatorAddrs.liquidator = address(proxy);
        liquidatorAddrs.liquidatorImplementation = address(liquidatorImplementation);
        liquidatorAddrs.protocolShareReserve = address(protocolShareReserve);
    }

    function deployPrimeOptional(
        Addresses memory addrs,
        address xvsToken,
        PrimeConfig memory config,
        PrimeBytecode memory bytecode
    ) external returns (PrimeAddresses memory primeAddrs) {
        require(deployedUnitroller != address(0), "not deployed");
        require(addrs.unitroller == deployedUnitroller, "wrong unitroller");
        require(xvsToken != address(0), "XVS zero");
        require(config.alphaNumerator != 0 && config.alphaNumerator < config.alphaDenominator, "bad alpha");
        require(config.loopsLimit != 0, "loops zero");
        require(config.primeMarkets.length == config.supplyMultipliers.length, "supply length");
        require(config.primeMarkets.length == config.borrowMultipliers.length, "borrow length");
        require(bytecode.xvsVaultProxyCreationCode.length != 0, "empty vault proxy code");
        require(bytecode.xvsVaultCreationCode.length != 0, "empty vault code");
        require(bytecode.xvsStoreCreationCode.length != 0, "empty store code");

        (primeAddrs.xvsVault, primeAddrs.xvsVaultImplementation, primeAddrs.xvsStore) = _deployPrimeVault(
            xvsToken,
            addrs.accessControlManager,
            config,
            bytecode
        );
        (primeAddrs.primeLiquidityProvider, primeAddrs.primeLiquidityProviderImplementation) = _deployPrimeLiquidityProvider(
            addrs.accessControlManager,
            config.blocksPerYear,
            config.loopsLimit
        );
        (primeAddrs.prime, primeAddrs.primeImplementation) = _deployPrimeToken(
            addrs,
            xvsToken,
            config,
            primeAddrs.xvsVault,
            primeAddrs.primeLiquidityProvider
        );
        _configurePrime(addrs, xvsToken, config, primeAddrs);
    }

    function _deployPrimeVault(
        address xvsToken,
        address accessControlManager,
        PrimeConfig memory config,
        PrimeBytecode memory bytecode
    ) internal returns (address xvsVaultProxy, address xvsVaultImplementation, address xvsStore) {
        xvsStore = _deployBytecode(bytecode.xvsStoreCreationCode, "deploy XVS store failed");
        xvsVaultProxy = _deployBytecode(bytecode.xvsVaultProxyCreationCode, "deploy XVS vault proxy failed");
        xvsVaultImplementation = _deployBytecode(bytecode.xvsVaultCreationCode, "deploy XVS vault failed");

        _callUint(xvsVaultProxy, abi.encodeWithSignature("_setPendingImplementation(address)", xvsVaultImplementation), "set vault implementation");
        _call(xvsVaultImplementation, abi.encodeWithSignature("_become(address)", xvsVaultProxy), "become vault");
        _call(xvsVaultProxy, abi.encodeWithSignature("setXvsStore(address,address)", xvsToken, xvsStore), "set XVS store");
        _call(xvsVaultProxy, abi.encodeWithSignature("setAccessControl(address)", accessControlManager), "set vault access control");
        _call(xvsVaultProxy, abi.encodeWithSignature("initializeTimeManager(bool,uint256)", false, config.blocksPerYear), "init vault time");
        _call(xvsStore, abi.encodeWithSignature("setNewOwner(address)", xvsVaultProxy), "set store owner");
        _call(
            xvsVaultProxy,
            abi.encodeWithSignature("add(address,uint256,address,uint256,uint256)", xvsToken, uint256(100), xvsToken, config.xvsVaultRewardPerBlock, config.xvsVaultLockPeriod),
            "add vault pool"
        );
    }

    function _deployPrimeLiquidityProvider(
        address accessControlManager,
        uint256 blocksPerYear,
        uint256 loopsLimit
    ) internal returns (address plp, address plpImplementation) {
        PrimeLiquidityProvider implementation = new PrimeLiquidityProvider(false, blocksPerYear);
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptySpeeds = new uint256[](0);
        bytes memory initData = abi.encodeCall(
            PrimeLiquidityProvider.initialize,
            (accessControlManager, emptyTokens, emptySpeeds, emptySpeeds, loopsLimit)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(0x000000000000000000000000000000000000Ad02),
            initData
        );
        plp = address(proxy);
        plpImplementation = address(implementation);
    }

    function _deployPrimeToken(
        Addresses memory addrs,
        address xvsToken,
        PrimeConfig memory config,
        address xvsVault,
        address plp
    ) internal returns (address prime, address primeImplementation) {
        Prime implementation = new Prime(
            addrs.wtao,
            addrs.vWTAO,
            config.blocksPerYear,
            config.stakingPeriod,
            config.minimumStakedXVS,
            config.maximumXVSCap,
            false
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(0x000000000000000000000000000000000000ad03),
            _primeInitData(addrs, xvsToken, config, xvsVault, plp)
        );
        prime = address(proxy);
        primeImplementation = address(implementation);
    }

    function _primeInitData(
        Addresses memory addrs,
        address xvsToken,
        PrimeConfig memory config,
        address xvsVault,
        address plp
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            Prime.initialize.selector,
            xvsVault,
            xvsToken,
            config.xvsVaultPoolId,
            config.alphaNumerator,
            config.alphaDenominator,
            addrs.accessControlManager,
            plp,
            addrs.unitroller,
            addrs.resilientOracle,
            config.loopsLimit
        );
    }

    function _configurePrime(
        Addresses memory addrs,
        address xvsToken,
        PrimeConfig memory config,
        PrimeAddresses memory primeAddrs
    ) internal {
        Prime livePrime = Prime(payable(primeAddrs.prime));
        PrimeLiquidityProvider(payable(primeAddrs.primeLiquidityProvider)).setPrimeToken(primeAddrs.prime);
        _call(
            primeAddrs.xvsVault,
            abi.encodeWithSignature("setPrimeToken(address,address,uint256)", primeAddrs.prime, xvsToken, config.xvsVaultPoolId),
            "set vault prime"
        );
        livePrime.initializeV2(address(0));
        livePrime.setLimit(config.irrevocableLimit, config.revocableLimit);
        for (uint256 i; i < config.primeMarkets.length; i++) {
            livePrime.addMarket(addrs.unitroller, config.primeMarkets[i], config.supplyMultipliers[i], config.borrowMultipliers[i]);
        }
        require(SetterFacet(addrs.unitroller)._setPrimeToken(IPrime(primeAddrs.prime)) == 0, "set comptroller prime");
        livePrime.togglePause();
    }

    function _readAddress(address target, string memory signature) internal view returns (address value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        require(ok, "address read failed");
        value = abi.decode(data, (address));
    }

    function _deployVAI(bytes memory vaiCreationCode) internal returns (address vai) {
        vai = _deployBytecode(vaiCreationCode, "deploy VAI failed");
    }

    function _deployBytecode(bytes memory creationCode, string memory errorMessage) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(deployed != address(0), errorMessage);
    }

    function _relyVAI(address vai, address ward) internal {
        (bool ok,) = vai.call(abi.encodeWithSignature("rely(address)", ward));
        require(ok, "VAI rely failed");
    }

    function _call(address target, bytes memory data, string memory errorMessage) internal {
        (bool ok,) = target.call(data);
        require(ok, errorMessage);
    }

    function _callUint(address target, bytes memory data, string memory errorMessage) internal {
        (bool ok, bytes memory result) = target.call(data);
        require(ok, errorMessage);
        require(abi.decode(result, (uint256)) == 0, errorMessage);
    }

    function _configurePhase3(SetterFacet liveSetter, Addresses memory addrs) internal {
        require(liveSetter.setCollateralFactor(VToken(addrs.vWTAO), 0, 0) == 0, "cf vWTAO");
        require(liveSetter.setCollateralFactor(VToken(addrs.vAlpha30), 0.25e18, 0.35e18) == 0, "cf vAlpha30");
        require(liveSetter.setCollateralFactor(VToken(addrs.vAlpha64), 0.25e18, 0.35e18) == 0, "cf vAlpha64");

        require(liveSetter.setLiquidationIncentive(addrs.vWTAO, 1.08e18) == 0, "li vWTAO");
        require(liveSetter.setLiquidationIncentive(addrs.vAlpha30, 1.08e18) == 0, "li vAlpha30");
        require(liveSetter.setLiquidationIncentive(addrs.vAlpha64, 1.08e18) == 0, "li vAlpha64");
        require(liveSetter._setCloseFactor(0.5e18) == 0, "close factor");

        VToken[] memory borrowCapTokens = new VToken[](3);
        uint256[] memory borrowCaps = new uint256[](3);
        borrowCapTokens[0] = VToken(addrs.vWTAO);
        borrowCapTokens[1] = VToken(addrs.vAlpha30);
        borrowCapTokens[2] = VToken(addrs.vAlpha64);
        borrowCaps[0] = type(uint256).max;
        liveSetter.setMarketBorrowCaps(borrowCapTokens, borrowCaps);

        VToken[] memory supplyCapTokens = new VToken[](3);
        uint256[] memory supplyCaps = new uint256[](3);
        supplyCapTokens[0] = VToken(addrs.vWTAO);
        supplyCapTokens[1] = VToken(addrs.vAlpha30);
        supplyCapTokens[2] = VToken(addrs.vAlpha64);
        supplyCaps[0] = type(uint256).max;
        supplyCaps[1] = type(uint256).max;
        supplyCaps[2] = type(uint256).max;
        liveSetter.setMarketSupplyCaps(supplyCapTokens, supplyCaps);

        liveSetter.setIsBorrowAllowed(0, addrs.vWTAO, true);
    }

    function _seedAndBurn(address underlying, address vToken, uint256 amount) internal {
        (bool mintOk,) = underlying.call(abi.encodeWithSignature("mint(address,uint256)", address(this), amount));
        require(mintOk, "underlying mint failed");
        require(IERC20(underlying).approve(vToken, amount), "underlying approve failed");

        VBep20Immutable market = VBep20Immutable(payable(vToken));
        uint256 beforeBalance = market.balanceOf(address(this));
        require(market.mint(amount) == 0, "seed mint failed");
        uint256 minted = market.balanceOf(address(this)) - beforeBalance;
        require(minted > 0, "no seed vtokens");
        require(market.transfer(DEAD, minted), "burn transfer failed");
    }

    function _buildFacetCut(
        MarketFacet marketFacet,
        PolicyFacet policyFacet,
        SetterFacet setterFacet,
        RewardFacet rewardFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](4);

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(marketFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _marketFacetSelectors()
        });
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(policyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _policyFacetSelectors()
        });
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(setterFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _setterFacetSelectors()
        });
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rewardFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _rewardFacetSelectors()
        });
    }

    function _marketFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](34);
        s[0] = MarketFacet.isComptroller.selector;
        s[1] = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,uint256)"));
        s[2] = bytes4(keccak256("liquidateCalculateSeizeTokens(address,address,address,uint256)"));
        s[3] = bytes4(keccak256("liquidateVAICalculateSeizeTokens(address,uint256)"));
        s[4] = MarketFacet.checkMembership.selector;
        s[5] = MarketFacet.enterMarketBehalf.selector;
        s[6] = MarketFacet.enterMarkets.selector;
        s[7] = MarketFacet.exitMarket.selector;
        s[8] = MarketFacet._supportMarket.selector;
        s[9] = MarketFacet.supportMarket.selector;
        s[10] = MarketFacet.isMarketListed.selector;
        s[11] = MarketFacet.getAssetsIn.selector;
        s[12] = MarketFacet.getAllMarkets.selector;
        s[13] = MarketFacet.updateDelegate.selector;
        s[14] = MarketFacet.unlistMarket.selector;
        s[15] = bytes4(keccak256("markets(address)"));
        s[16] = MarketFacet.getCollateralFactor.selector;
        s[17] = MarketFacet.getLiquidationThreshold.selector;
        s[18] = MarketFacet.getLiquidationIncentive.selector;
        s[19] = MarketFacet.getEffectiveLiquidationIncentive.selector;
        s[20] = bytes4(keccak256("getEffectiveLtvFactor(address,address,uint8)"));
        s[21] = bytes4(keccak256("oracle()"));
        s[22] = bytes4(keccak256("comptrollerLens()"));
        s[23] = bytes4(keccak256("liquidatorContract()"));
        s[24] = bytes4(keccak256("closeFactorMantissa()"));
        s[25] = bytes4(keccak256("pauseGuardian()"));
        s[26] = bytes4(keccak256("borrowCapGuardian()"));
        s[27] = bytes4(keccak256("borrowCaps(address)"));
        s[28] = bytes4(keccak256("supplyCaps(address)"));
        s[29] = bytes4(keccak256("approvedDelegates(address,address)"));
        s[30] = bytes4(keccak256("isForcedLiquidationEnabled(address)"));
        s[31] = bytes4(keccak256("actionPaused(address,uint8)"));
        s[32] = bytes4(keccak256("venusSupplySpeeds(address)"));
        s[33] = bytes4(keccak256("venusBorrowSpeeds(address)"));
    }

    function _policyFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](17);
        s[0] = PolicyFacet.mintAllowed.selector;
        s[1] = PolicyFacet.mintVerify.selector;
        s[2] = PolicyFacet.redeemAllowed.selector;
        s[3] = PolicyFacet.redeemVerify.selector;
        s[4] = PolicyFacet.borrowAllowed.selector;
        s[5] = PolicyFacet.borrowVerify.selector;
        s[6] = PolicyFacet.repayBorrowAllowed.selector;
        s[7] = PolicyFacet.repayBorrowVerify.selector;
        s[8] = PolicyFacet.liquidateBorrowAllowed.selector;
        s[9] = PolicyFacet.liquidateBorrowVerify.selector;
        s[10] = PolicyFacet.seizeAllowed.selector;
        s[11] = PolicyFacet.seizeVerify.selector;
        s[12] = PolicyFacet.transferAllowed.selector;
        s[13] = PolicyFacet.transferVerify.selector;
        s[14] = PolicyFacet.getAccountLiquidity.selector;
        s[15] = PolicyFacet.getHypotheticalAccountLiquidity.selector;
        s[16] = bytes4(keccak256("_setVenusSpeeds(address[],uint256[],uint256[])"));
    }

    function _setterFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](19);
        s[0] = SetterFacet._setPriceOracle.selector;
        s[1] = SetterFacet._setComptrollerLens.selector;
        s[2] = SetterFacet._setAccessControl.selector;
        s[3] = SetterFacet._setCloseFactor.selector;
        s[4] = bytes4(keccak256("setCollateralFactor(address,uint256,uint256)"));
        s[5] = bytes4(keccak256("setLiquidationIncentive(address,uint256)"));
        s[6] = bytes4(keccak256("setIsBorrowAllowed(uint96,address,bool)"));
        s[7] = SetterFacet.setMarketBorrowCaps.selector;
        s[8] = SetterFacet.setMarketSupplyCaps.selector;
        s[9] = SetterFacet._setLiquidatorContract.selector;
        s[10] = SetterFacet._setPauseGuardian.selector;
        s[11] = SetterFacet._setProtocolPaused.selector;
        s[12] = bytes4(keccak256("_setXVSToken(address)"));
        s[13] = SetterFacet._setVAIController.selector;
        s[14] = SetterFacet._setVAIMintRate.selector;
        s[15] = SetterFacet.setMintedVAIOf.selector;
        s[16] = bytes4(keccak256("_setActionsPaused(address[],uint8[],bool)"));
        s[17] = SetterFacet.setPrimeToken.selector;
        s[18] = SetterFacet._setPrimeToken.selector;
    }

    function _rewardFacetSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = bytes4(keccak256("claimVenus(address)"));
        s[1] = RewardFacet.getXVSVTokenAddress.selector;
        s[2] = bytes4(keccak256("claimVenus(address,address[])"));
        s[3] = bytes4(keccak256("claimVenus(address[],address[],bool,bool)"));
        s[4] = bytes4(keccak256("claimVenusAsCollateral(address)"));
        s[5] = bytes4(keccak256("_grantXVS(address,uint256)"));
        s[6] = bytes4(keccak256("seizeVenus(address[],address)"));
        s[7] = bytes4(keccak256("getXVSAddress()"));
    }
}
