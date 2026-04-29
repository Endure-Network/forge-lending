// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {IAccessControlManagerV8} from
    "@venusprotocol/governance-contracts/contracts/Governance/IAccessControlManagerV8.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title DenyAllAccessControlManager
/// @notice Endure-authored mock implementing Venus IAccessControlManagerV8 for negative-path ACM tests.
/// @dev All permission checks unconditionally return false (deny-all). All mutating functions are no-ops.
///      Mirrors AllowAllAccessControlManager but flips all booleans.
///
///      Used to prove that swapping the ACM from AllowAll to DenyAll blocks previously-allowed
///      admin operations in Venus Diamond-based comptroller tests.
///
///      NOT FOR PRODUCTION USE. Deploy only in test environments.
contract DenyAllAccessControlManager is IAccessControlManagerV8 {
    // --- IAccessControlManagerV8 ---

    /// @inheritdoc IAccessControlManagerV8
    /// @dev No-op: mock does not track call permissions.
    function giveCallPermission(
        address, /* contractAddress */
        string calldata, /* functionSig */
        address /* accountToPermit */
    ) external override {}

    /// @inheritdoc IAccessControlManagerV8
    /// @dev No-op: mock does not track call permissions.
    function revokeCallPermission(
        address, /* contractAddress */
        string calldata, /* functionSig */
        address /* accountToRevoke */
    ) external override {}

    /// @inheritdoc IAccessControlManagerV8
    /// @return false always — deny-all.
    function isAllowedToCall(
        address, /* account */
        string calldata /* functionSig */
    ) external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IAccessControlManagerV8
    /// @return false always — deny-all.
    function hasPermission(
        address, /* account */
        address, /* contractAddress */
        string calldata /* functionSig */
    ) external pure override returns (bool) {
        return false;
    }

    // --- IAccessControl (OpenZeppelin) ---

    /// @inheritdoc IAccessControl
    /// @return false always — deny-all.
    function hasRole(bytes32, /* role */ address /* account */ ) external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IAccessControl
    /// @return bytes32(0) — no role hierarchy in the mock.
    function getRoleAdmin(bytes32 /* role */ ) external pure override returns (bytes32) {
        return bytes32(0);
    }

    /// @inheritdoc IAccessControl
    /// @dev No-op: mock does not track role assignments.
    function grantRole(bytes32, /* role */ address /* account */ ) external override {}

    /// @inheritdoc IAccessControl
    /// @dev No-op: mock does not track role assignments.
    function revokeRole(bytes32, /* role */ address /* account */ ) external override {}

    /// @inheritdoc IAccessControl
    /// @dev No-op: mock does not track role assignments.
    function renounceRole(bytes32, /* role */ address /* account */ ) external override {}
}
