// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

library EndureRoles {
    struct RoleSet {
        address admin;
        address pauseGuardian;
        address borrowCapGuardian;
        address supplyCapGuardian;
    }

    function allEqual(RoleSet memory r, address who) internal pure returns (bool) {
        return r.admin == who && r.pauseGuardian == who && r.borrowCapGuardian == who && r.supplyCapGuardian == who;
    }
}
