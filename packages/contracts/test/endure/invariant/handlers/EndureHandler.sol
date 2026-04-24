// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MockPriceOracle} from "@protocol/endure/MockPriceOracle.sol";
import {MToken} from "@protocol/MToken.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";

contract EndureHandler is Test {
    Comptroller public comptroller;
    MErc20Delegator public mWTAO;
    MErc20Delegator public mMockAlpha30;
    WTAO public wtao;
    MockAlpha30 public mockAlpha30;
    MockPriceOracle public mockOracle;

    mapping(string => uint256) public callCounts;
    address[] public actors;

    uint256 internal constant NUM_ACTORS = 3;

    constructor(
        address _comptroller,
        address _mWTAO,
        address _mMockAlpha30,
        address _wtao,
        address _mockAlpha30,
        address _mockOracle
    ) {
        comptroller = Comptroller(_comptroller);
        mWTAO = MErc20Delegator(payable(_mWTAO));
        mMockAlpha30 = MErc20Delegator(payable(_mMockAlpha30));
        wtao = WTAO(_wtao);
        mockAlpha30 = MockAlpha30(_mockAlpha30);
        mockOracle = MockPriceOracle(_mockOracle);

        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", vm.toString(i)))));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % NUM_ACTORS];
    }

    function supply(uint256 actorSeed, uint256 amount) external {
        callCounts["supply"]++;

        amount = bound(amount, 1e15, 1000e18);

        address actor = _actor(actorSeed);
        mockAlpha30.mint(actor, amount);

        vm.startPrank(actor);
        mockAlpha30.approve(address(mMockAlpha30), amount);
        mMockAlpha30.mint(amount);

        address[] memory markets = new address[](1);
        markets[0] = address(mMockAlpha30);
        comptroller.enterMarkets(markets);
        vm.stopPrank();
    }

    function borrow(uint256 actorSeed, uint256 amount) external {
        callCounts["borrow"]++;

        amount = bound(amount, 1e15, 100e18);

        address actor = _actor(actorSeed);

        wtao.mint(address(this), amount * 2);
        wtao.approve(address(mWTAO), amount * 2);
        mWTAO.mint(amount * 2);

        vm.prank(actor);
        mWTAO.borrow(amount);
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        callCounts["repay"]++;

        address actor = _actor(actorSeed);
        uint256 debt = mWTAO.borrowBalanceCurrent(actor);
        if (debt == 0) {
            return;
        }

        amount = bound(amount, 1, debt);

        wtao.mint(actor, amount);
        vm.startPrank(actor);
        wtao.approve(address(mWTAO), amount);
        mWTAO.repayBorrow(amount);
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 amount) external {
        callCounts["redeem"]++;

        address actor = _actor(actorSeed);
        uint256 bal = mMockAlpha30.balanceOf(actor);
        if (bal == 0) {
            return;
        }

        amount = bound(amount, 1, bal);

        vm.prank(actor);
        mMockAlpha30.redeem(amount);
    }

    function liquidate(uint256 actorSeed, uint256 amount) external {
        callCounts["liquidate"]++;

        address borrower = _actor(actorSeed);
        uint256 debt = mWTAO.borrowBalanceCurrent(borrower);
        if (debt == 0) {
            return;
        }

        (, , uint256 shortfall) = comptroller.getAccountLiquidity(borrower);
        if (shortfall == 0) {
            return;
        }

        uint256 maxRepay = debt / 2;
        if (maxRepay == 0) {
            maxRepay = debt;
        }

        amount = bound(amount, 1, maxRepay);

        address liquidator = makeAddr("liquidator");
        wtao.mint(liquidator, amount);
        vm.startPrank(liquidator);
        wtao.approve(address(mWTAO), amount);
        mWTAO.liquidateBorrow(borrower, amount, mMockAlpha30);
        vm.stopPrank();
    }

    function moveOraclePrice(uint256, uint256 deltaSeed) external {
        callCounts["moveOraclePrice"]++;
        uint256 newPrice = bound(deltaSeed, 0.1e18, 10e18);
        mockOracle.setUnderlyingPrice(MToken(address(mMockAlpha30)), newPrice);
    }
}
