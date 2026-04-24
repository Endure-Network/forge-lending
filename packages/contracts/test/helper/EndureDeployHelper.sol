// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";
import {MockPriceOracle} from "@protocol/endure/MockPriceOracle.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MockAlpha64} from "@protocol/endure/MockAlpha64.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {EnduRateModelParams} from "@protocol/endure/EnduRateModelParams.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MToken} from "@protocol/MToken.sol";

abstract contract EndureDeployHelper is Test {
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    struct Addresses {
        address comptrollerProxy;
        address comptrollerImpl;
        address mockPriceOracle;
        address wtao;
        address mockAlpha30;
        address mockAlpha64;
        address mWTAO;
        address mMockAlpha30;
        address mMockAlpha64;
        address jumpRateModel_mWTAO;
        address jumpRateModel_mMockAlpha30;
        address jumpRateModel_mMockAlpha64;
        address mErc20Delegate;
    }

    struct MarketConfig {
        string name;
        string symbol;
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        uint256 collateralFactor;
        uint256 supplyCap;
        uint256 borrowCap;
    }

    function _deploy() internal returns (Addresses memory) {
        EndureRoles.RoleSet memory roles = EndureRoles.RoleSet({
            admin: msg.sender,
            pauseGuardian: msg.sender,
            borrowCapGuardian: msg.sender,
            supplyCapGuardian: msg.sender
        });
        return _deployWithRoles(roles);
    }

    function _deployAs(
        EndureRoles.RoleSet memory roles
    ) internal returns (Addresses memory addrs) {
        vm.startPrank(roles.admin);
        addrs = _deployWithRoles(roles);
        vm.stopPrank();
    }

    function _deployWithRoles(
        EndureRoles.RoleSet memory roles
    ) private returns (Addresses memory addrs) {
        Comptroller comptrollerImplementation = new Comptroller();
        Unitroller unitroller = new Unitroller();
        require(
            unitroller._setPendingImplementation(address(comptrollerImplementation)) == 0,
            "set pending implementation failed"
        );
        comptrollerImplementation._become(unitroller);

        Comptroller live = Comptroller(address(unitroller));
        MockPriceOracle mockOracle = new MockPriceOracle();
        require(live._setPriceOracle(mockOracle) == 0, "set oracle failed");
        require(
            live._setCloseFactor(EnduRateModelParams.CLOSE_FACTOR) == 0,
            "set close factor failed"
        );
        require(
            live._setLiquidationIncentive(EnduRateModelParams.LIQUIDATION_INCENTIVE) == 0,
            "set liquidation incentive failed"
        );
        require(
            live._setPauseGuardian(roles.pauseGuardian) == 0,
            "set pause guardian failed"
        );
        live._setBorrowCapGuardian(roles.borrowCapGuardian);
        live._setSupplyCapGuardian(roles.supplyCapGuardian);

        MErc20Delegate mErc20Delegate = new MErc20Delegate();
        WTAO wtao = new WTAO();
        MockAlpha30 mockAlpha30 = new MockAlpha30();
        MockAlpha64 mockAlpha64 = new MockAlpha64();

        addrs.comptrollerProxy = address(unitroller);
        addrs.comptrollerImpl = address(comptrollerImplementation);
        addrs.mockPriceOracle = address(mockOracle);
        addrs.wtao = address(wtao);
        addrs.mockAlpha30 = address(mockAlpha30);
        addrs.mockAlpha64 = address(mockAlpha64);
        addrs.mErc20Delegate = address(mErc20Delegate);

        MarketConfig memory config = MarketConfig({
            name: "Moonwell WTAO",
            symbol: "mWTAO",
            baseRatePerYear: EnduRateModelParams.WTAO_BASE_RATE_PER_YEAR,
            multiplierPerYear: EnduRateModelParams.WTAO_MULTIPLIER_PER_YEAR,
            jumpMultiplierPerYear: EnduRateModelParams.WTAO_JUMP_MULTIPLIER_PER_YEAR,
            kink: EnduRateModelParams.WTAO_KINK,
            collateralFactor: EnduRateModelParams.COLLATERAL_FACTOR_WTAO,
            supplyCap: type(uint256).max,
            borrowCap: EnduRateModelParams.BORROW_CAP_WTAO
        });
        (addrs.jumpRateModel_mWTAO, addrs.mWTAO) = _listMarket(
            live,
            mockOracle,
            roles.admin,
            address(wtao),
            config,
            address(mErc20Delegate)
        );

        config = MarketConfig({
            name: "Moonwell Mock Alpha 30",
            symbol: "mMockAlpha30",
            baseRatePerYear: EnduRateModelParams.ALPHA_BASE_RATE_PER_YEAR,
            multiplierPerYear: EnduRateModelParams.ALPHA_MULTIPLIER_PER_YEAR,
            jumpMultiplierPerYear: EnduRateModelParams.ALPHA_JUMP_MULTIPLIER_PER_YEAR,
            kink: EnduRateModelParams.ALPHA_KINK,
            collateralFactor: EnduRateModelParams.COLLATERAL_FACTOR_ALPHA,
            supplyCap: EnduRateModelParams.SUPPLY_CAP_ALPHA,
            borrowCap: EnduRateModelParams.BORROW_CAP_ALPHA
        });
        (addrs.jumpRateModel_mMockAlpha30, addrs.mMockAlpha30) = _listMarket(
            live,
            mockOracle,
            roles.admin,
            address(mockAlpha30),
            config,
            address(mErc20Delegate)
        );

        config.name = "Moonwell Mock Alpha 64";
        config.symbol = "mMockAlpha64";
        (addrs.jumpRateModel_mMockAlpha64, addrs.mMockAlpha64) = _listMarket(
            live,
            mockOracle,
            roles.admin,
            address(mockAlpha64),
            config,
            address(mErc20Delegate)
        );
    }

    function _listMarket(
        Comptroller comptroller,
        MockPriceOracle mockOracle,
        address admin,
        address underlying,
        MarketConfig memory config,
        address implementation
    ) private returns (address jumpRateModel, address mToken) {
        JumpRateModel irm = new JumpRateModel(
            config.baseRatePerYear,
            config.multiplierPerYear,
            config.jumpMultiplierPerYear,
            config.kink
        );
        MErc20Delegator delegator = new MErc20Delegator(
            underlying,
            comptroller,
            irm,
            EnduRateModelParams.INITIAL_EXCHANGE_RATE_MANTISSA,
            config.name,
            config.symbol,
            EIP20Interface(underlying).decimals(),
            payable(admin),
            implementation,
            ""
        );
        require(
            comptroller._supportMarket(MToken(address(delegator))) == 0,
            "support market failed"
        );
        mockOracle.setUnderlyingPrice(MToken(address(delegator)), 1e18);
        require(
            comptroller._setCollateralFactor(MToken(address(delegator)), config.collateralFactor) == 0,
            "set collateral factor failed"
        );

        MToken[] memory markets = new MToken[](1);
        markets[0] = MToken(address(delegator));
        uint256[] memory caps = new uint256[](1);

        caps[0] = config.supplyCap;
        comptroller._setMarketSupplyCaps(markets, caps);
        caps[0] = config.borrowCap;
        comptroller._setMarketBorrowCaps(markets, caps);
        require(
            delegator._setReserveFactor(EnduRateModelParams.RESERVE_FACTOR) == 0,
            "set reserve factor failed"
        );
        _seedAndBurn(admin, underlying, delegator);

        return (address(irm), address(delegator));
    }

    function _seedAndBurn(
        address admin,
        address underlying,
        MErc20Delegator mToken
    ) private {
        (bool mintOk, ) = underlying.call(
            abi.encodeWithSignature(
                "mint(address,uint256)",
                admin,
                EnduRateModelParams.SEED_AMOUNT
            )
        );
        require(mintOk, "underlying mint failed");
        require(
            EIP20Interface(underlying).approve(
                address(mToken),
                EnduRateModelParams.SEED_AMOUNT
            ),
            "approve failed"
        );
        require(
            mToken.mint(EnduRateModelParams.SEED_AMOUNT) == 0,
            "seed mint failed"
        );
        require(
            mToken.transfer(DEAD, mToken.balanceOf(admin)),
            "burn transfer failed"
        );
    }
}
