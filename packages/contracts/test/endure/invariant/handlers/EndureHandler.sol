// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/venus-staging/Tokens/VTokens/VToken.sol";
import {MarketFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";

contract EndureHandler is Test {
    address public unitroller;
    VBep20Immutable public vWTAO;
    VBep20Immutable public vAlpha30;
    WTAO public wtao;
    MockAlpha30 public mockAlpha30;
    MockResilientOracle public oracle;
    address public vAlpha30Addr;

    mapping(string => uint256) public callCounts;
    address[] public actors;

    uint256 internal constant NUM_ACTORS = 3;

    constructor(
        address _unitroller,
        address _vWTAO,
        address _vAlpha30,
        address _wtao,
        address _mockAlpha30,
        address _oracle
    ) {
        unitroller = _unitroller;
        vWTAO = VBep20Immutable(payable(_vWTAO));
        vAlpha30 = VBep20Immutable(payable(_vAlpha30));
        vAlpha30Addr = _vAlpha30;
        wtao = WTAO(_wtao);
        mockAlpha30 = MockAlpha30(_mockAlpha30);
        oracle = MockResilientOracle(_oracle);

        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", vm.toString(i)))));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % NUM_ACTORS];
    }

    function supply(uint256 actorSeed, uint256 amount) external {
        callCounts["supply"]++;
        amount = bound(amount, 1e15, 1_000e18);

        address actor = _actor(actorSeed);
        mockAlpha30.mint(actor, amount);

        vm.startPrank(actor);
        mockAlpha30.approve(address(vAlpha30), amount);
        vAlpha30.mint(amount);

        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        MarketFacet(unitroller).enterMarkets(markets);
        vm.stopPrank();
    }

    function borrow(uint256 actorSeed, uint256 amount) external {
        callCounts["borrow"]++;
        amount = bound(amount, 1e15, 100e18);

        address actor = _actor(actorSeed);

        // Ensure WTAO liquidity
        wtao.mint(address(this), amount * 2);
        wtao.approve(address(vWTAO), amount * 2);
        vWTAO.mint(amount * 2);

        vm.prank(actor);
        vWTAO.borrow(amount);
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        callCounts["repay"]++;

        address actor = _actor(actorSeed);
        uint256 debt = vWTAO.borrowBalanceCurrent(actor);
        if (debt == 0) return;

        amount = bound(amount, 1, debt);

        wtao.mint(actor, amount);
        vm.startPrank(actor);
        wtao.approve(address(vWTAO), amount);
        vWTAO.repayBorrow(amount);
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 amount) external {
        callCounts["redeem"]++;

        address actor = _actor(actorSeed);
        uint256 bal = vAlpha30.balanceOf(actor);
        if (bal == 0) return;

        amount = bound(amount, 1, bal);

        vm.prank(actor);
        vAlpha30.redeem(amount);
    }

    function liquidate(uint256 actorSeed, uint256 amount) external {
        callCounts["liquidate"]++;

        address borrower = _actor(actorSeed);
        uint256 debt = vWTAO.borrowBalanceCurrent(borrower);
        if (debt == 0) return;

        (, , uint256 shortfall) = PolicyFacet(unitroller).getAccountLiquidity(borrower);
        if (shortfall == 0) return;

        uint256 maxRepay = debt / 2;
        if (maxRepay == 0) maxRepay = debt;

        amount = bound(amount, 1, maxRepay);

        address liquidator = makeAddr("liquidator");
        wtao.mint(liquidator, amount);
        vm.startPrank(liquidator);
        wtao.approve(address(vWTAO), amount);
        vWTAO.liquidateBorrow(borrower, amount, VToken(address(vAlpha30)));
        vm.stopPrank();
    }

    function moveOraclePrice(uint256, uint256 deltaSeed) external {
        callCounts["moveOraclePrice"]++;
        uint256 newPrice = bound(deltaSeed, 0.1e18, 10e18);
        oracle.setUnderlyingPrice(vAlpha30Addr, newPrice);
    }
}
