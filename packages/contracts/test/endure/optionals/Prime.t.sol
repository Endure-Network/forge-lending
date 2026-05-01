// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {MockXVS} from "@protocol/endure/MockXVS.sol";
import {Prime} from "@protocol/Tokens/Prime/Prime.sol";
import {PrimeLiquidityProvider} from "@protocol/Tokens/Prime/PrimeLiquidityProvider.sol";

contract PrimeOptionalTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;
    MockXVS xvs;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        xvs = new MockXVS();
        xvs.mint(address(this), 10_000e18);
        xvs.approve(address(helper), type(uint256).max);
    }

    function test_DeployPrimeOptional_WiresPrimeVaultLiquidityProviderAndComptroller() public {
        EndureDeployHelper.PrimeAddresses memory primeAddrs = helper.deployPrimeOptional(
            addrs,
            address(xvs),
            _defaultPrimeConfig(),
            _primeBytecode()
        );

        assertTrue(primeAddrs.prime != address(0), "prime");
        assertTrue(primeAddrs.primeImplementation != address(0), "prime implementation");
        assertTrue(primeAddrs.primeLiquidityProvider != address(0), "plp");
        assertTrue(primeAddrs.primeLiquidityProviderImplementation != address(0), "plp implementation");
        assertTrue(primeAddrs.xvsVault != address(0), "xvs vault");
        assertTrue(primeAddrs.xvsVaultImplementation != address(0), "xvs vault implementation");
        assertTrue(primeAddrs.xvsStore != address(0), "xvs store");

        assertEq(Prime(payable(primeAddrs.prime)).xvsVault(), primeAddrs.xvsVault, "prime vault");
        assertEq(Prime(payable(primeAddrs.prime)).xvsVaultRewardToken(), address(xvs), "prime reward token");
        assertEq(Prime(payable(primeAddrs.prime)).primeLiquidityProvider(), primeAddrs.primeLiquidityProvider, "prime plp");
        assertEq(Prime(payable(primeAddrs.prime)).alphaNumerator(), 1, "alpha numerator");
        assertEq(Prime(payable(primeAddrs.prime)).alphaDenominator(), 2, "alpha denominator");
        assertEq(Prime(payable(primeAddrs.prime)).irrevocableLimit(), 1000, "irrevocable limit");
        assertEq(Prime(payable(primeAddrs.prime)).revocableLimit(), 1000, "revocable limit");
        assertFalse(Prime(payable(primeAddrs.prime)).paused(), "prime unpaused");

        assertEq(PrimeLiquidityProvider(payable(primeAddrs.primeLiquidityProvider)).prime(), primeAddrs.prime, "plp prime");
        assertEq(IComptrollerPrime(addrs.unitroller).prime(), primeAddrs.prime, "comptroller prime");
        assertEq(IXVSVaultPrime(primeAddrs.xvsVault).primeToken(), primeAddrs.prime, "vault prime");

        (uint256 supplyMultiplier, uint256 borrowMultiplier,,, bool exists) = IPrimeMarket(primeAddrs.prime).markets(addrs.vWTAO);
        assertTrue(exists, "prime market");
        assertEq(supplyMultiplier, 1e18, "supply multiplier");
        assertEq(borrowMultiplier, 1e18, "borrow multiplier");
    }

    function test_DeployPrimeOptional_UserCanStakeAndClaimPrimeToken() public {
        EndureDeployHelper.PrimeAddresses memory primeAddrs = helper.deployPrimeOptional(
            addrs,
            address(xvs),
            _defaultPrimeConfig(),
            _primeBytecode()
        );
        address user = makeAddr("prime user");
        uint256 stakeAmount = 1000e18;

        xvs.mint(user, stakeAmount);

        vm.startPrank(user);
        xvs.approve(primeAddrs.xvsVault, stakeAmount);
        IXVSVaultPrime(primeAddrs.xvsVault).deposit(address(xvs), 0, stakeAmount);
        vm.warp(block.timestamp + 601);
        Prime(payable(primeAddrs.prime)).claim();
        vm.stopPrank();

        assertTrue(Prime(payable(primeAddrs.prime)).isUserPrimeHolder(user), "prime holder");
    }

    function test_DeployPrimeOptional_FundsXVSStoreForVaultRewards() public {
        EndureDeployHelper.PrimeAddresses memory primeAddrs = helper.deployPrimeOptional(
            addrs,
            address(xvs),
            _defaultPrimeConfig(),
            _primeBytecode()
        );

        assertEq(xvs.balanceOf(primeAddrs.xvsStore), 1000e18, "xvs store funding");
    }

    function test_DeployPrimeOptional_RevertsIfXVSZero() public {
        vm.expectRevert(bytes("XVS zero"));
        helper.deployPrimeOptional(addrs, address(0), _defaultPrimeConfig(), _primeBytecode());
    }

    function test_DeployPrimeOptional_RevertsIfAlphaRatioInvalid() public {
        EndureDeployHelper.PrimeConfig memory config = _defaultPrimeConfig();
        config.alphaNumerator = config.alphaDenominator;

        vm.expectRevert(bytes("bad alpha"));
        helper.deployPrimeOptional(addrs, address(xvs), config, _primeBytecode());
    }

    function test_DeployPrimeOptional_RevertsIfSupplyMultiplierLengthMismatchesMarkets() public {
        EndureDeployHelper.PrimeConfig memory config = _defaultPrimeConfig();
        config.supplyMultipliers = new uint256[](0);

        vm.expectRevert(bytes("supply length"));
        helper.deployPrimeOptional(addrs, address(xvs), config, _primeBytecode());
    }

    function test_DeployPrimeOptional_RevertsIfVaultProxyBytecodeEmpty() public {
        EndureDeployHelper.PrimeBytecode memory bytecode = _primeBytecode();
        bytecode.xvsVaultProxyCreationCode = "";

        vm.expectRevert(bytes("empty vault proxy code"));
        helper.deployPrimeOptional(addrs, address(xvs), _defaultPrimeConfig(), bytecode);
    }

    function _defaultPrimeConfig() internal view returns (EndureDeployHelper.PrimeConfig memory) {
        address[] memory markets = new address[](1);
        markets[0] = addrs.vWTAO;
        uint256[] memory supplyMultipliers = new uint256[](1);
        supplyMultipliers[0] = 1e18;
        uint256[] memory borrowMultipliers = new uint256[](1);
        borrowMultipliers[0] = 1e18;

        return EndureDeployHelper.PrimeConfig({
            blocksPerYear: 100,
            stakingPeriod: 600,
            minimumStakedXVS: 1000e18,
            maximumXVSCap: 100000e18,
            xvsVaultPoolId: 0,
            xvsVaultRewardPerBlock: 1e18,
            xvsVaultRewardFundingAmount: 1000e18,
            xvsVaultLockPeriod: 300,
            alphaNumerator: 1,
            alphaDenominator: 2,
            loopsLimit: 20,
            irrevocableLimit: 1000,
            revocableLimit: 1000,
            primeMarkets: markets,
            supplyMultipliers: supplyMultipliers,
            borrowMultipliers: borrowMultipliers
        });
    }

    function _primeBytecode() internal view returns (EndureDeployHelper.PrimeBytecode memory) {
        return EndureDeployHelper.PrimeBytecode({
            xvsVaultProxyCreationCode: vm.getCode("out/XVSVaultProxy.sol/XVSVaultProxy.0.5.16.json"),
            xvsVaultCreationCode: vm.getCode("out/XVSVault.sol/XVSVault.json"),
            xvsStoreCreationCode: vm.getCode("out/XVSStore.sol/XVSStore.json")
        });
    }
}

interface IComptrollerPrime {
    function prime() external view returns (address);
}

interface IPrimeMarket {
    function markets(address market) external view returns (
        uint256 supplyMultiplier,
        uint256 borrowMultiplier,
        uint256 rewardIndex,
        uint256 sumOfMembersScore,
        bool exists
    );
}

interface IXVSVaultPrime {
    function primeToken() external view returns (address);

    function deposit(address rewardToken, uint256 pid, uint256 amount) external;
}
