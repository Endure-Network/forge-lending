// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {OracleInterface, ResilientOracleInterface} from "@venusprotocol/oracle/contracts/interfaces/OracleInterface.sol";

/// @title MockResilientOracle
/// @notice Endure-authored mock implementing Venus ResilientOracleInterface for Phase 0.5 Stage A spike testing.
/// @dev Admin-set prices per vToken (via setUnderlyingPrice) and per underlying asset (via setDirectPrice).
///      updatePrice and updateAssetPrice are intentional no-ops — Venus calls these to refresh oracle feeds;
///      in the mock there are no feeds to refresh.
///      NOT FOR PRODUCTION USE.
contract MockResilientOracle is ResilientOracleInterface {
    address public admin;

    /// @notice Prices keyed by vToken address, returned by getUnderlyingPrice.
    ///         Scaled to 1e18 as Venus expects (i.e. price of the underlying in USD * 1e18).
    mapping(address => uint256) public underlyingPrices;

    /// @notice Prices keyed by underlying asset address, returned by getPrice.
    mapping(address => uint256) public directPrices;

    event UnderlyingPriceSet(address indexed vToken, uint256 priceMantissa);
    event DirectPriceSet(address indexed asset, uint256 price);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    // ─── Admin setters ────────────────────────────────────────────────────────

    /// @notice Set the underlying price for a vToken (1e18-scaled USD price of the underlying).
    function setUnderlyingPrice(address vToken, uint256 priceMantissa) external onlyAdmin {
        underlyingPrices[vToken] = priceMantissa;
        emit UnderlyingPriceSet(vToken, priceMantissa);
    }

    /// @notice Set the direct price for an underlying asset address.
    function setDirectPrice(address asset, uint256 price) external onlyAdmin {
        directPrices[asset] = price;
        emit DirectPriceSet(asset, price);
    }

    /// @notice Transfer admin in one step. New admin must be non-zero.
    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "new admin = 0");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    // ─── ResilientOracleInterface ─────────────────────────────────────────────

    /// @inheritdoc ResilientOracleInterface
    /// @dev No-op: mock has no underlying oracle feeds to refresh.
    function updatePrice(address /* vToken */ ) external override {}

    /// @inheritdoc ResilientOracleInterface
    /// @dev No-op: mock has no underlying oracle feeds to refresh.
    function updateAssetPrice(address /* asset */ ) external override {}

    /// @inheritdoc ResilientOracleInterface
    /// @return Price set via setUnderlyingPrice for this vToken, or 0 if unset.
    function getUnderlyingPrice(address vToken) external view override returns (uint256) {
        return underlyingPrices[vToken];
    }

    // ─── OracleInterface ──────────────────────────────────────────────────────

    /// @inheritdoc OracleInterface
    /// @return Price set via setDirectPrice for this asset, or 0 if unset.
    function getPrice(address asset) external view override returns (uint256) {
        return directPrices[asset];
    }
}
