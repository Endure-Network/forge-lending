# Security Policy

## Scope

This repository hosts the Endure Network protocol — a lending protocol forked
from Venus Protocol Core Pool, pinned at upstream commit
`6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`), BSD-3-Clause
licensed. Phase 0 (current) is local Anvil only; no mainnet or testnet
deployment has occurred and no user funds are at risk.

Security-relevant surfaces during Phase 0:

- **Fork discipline (Stance B)**: kept Venus source files must remain
  byte-identical to pinned upstream commit
  `6400a067114a101bd3bebfca2a4bd06480e84831`. Any deviation is a fork-hygiene
  issue.
- **Venus architecture components**: Diamond proxy via Unitroller, facets
  (MarketFacet, PolicyFacet, SetterFacet, RewardFacet), AccessControlManager,
  and VBep20Immutable markets.
- **Endure-authored code** in `packages/contracts/src/endure/`, deploy scripts,
  and helper contracts.
- **Phase 0 surfaces**: vWTAO (borrowable, CF/LT=0%), vAlpha30/vAlpha64
  (collateral-only, CF=25%/LT=35%, borrow blocked).
- **Build and deploy pipeline** (`foundry.toml`, `DeployLocal.s.sol`,
  `scripts/*.sh`).

Out of scope for Phase 0:
- Production deployment risks (Phase 1+)
- Keeper / oracle / adapter security (Phase 2-4)

Audits are planned for Phase 4 (see `skills/endure-architecture/SKILL.md`
§ "Phase 4").

## Reporting a Vulnerability

**Do not open a public GitHub issue for security-sensitive reports.**

Preferred channels:

1. **GitHub private vulnerability advisory**: use the "Report a vulnerability"
   button under the Security tab of this repository
   (`https://github.com/Endure-Network/forge-lending/security/advisories/new`).
   This creates a private advisory visible only to maintainers.
2. **Direct email**: `hello@apeguru.dev` (org admin contact on record).

Please include:

- Affected file(s), commit SHA, and line references
- A minimal reproduction (ideally a Foundry test or a command sequence)
- Your assessment of severity and affected code paths
- Any proposed mitigation

## Response SLA (Phase 0 best-effort)

- **Acknowledgement**: within 3 business days
- **Initial assessment**: within 7 business days
- **Fix or mitigation plan**: depends on severity; critical issues prioritised

Formal SLAs, bounty terms, and responsible-disclosure timelines will be
published before any mainnet deployment (Phase 4).

## Handling of Upstream Venus Vulnerabilities

Endure is forked at a pinned commit. If a vulnerability is disclosed against
upstream `VenusProtocol/venus-protocol`:

1. Maintainers evaluate whether the affected file is kept in the Endure fork
   (see `packages/contracts/FORK_MANIFEST.md` § 4).
2. If affected and fixable without diverging from Stance B, the patch is
   backported and recorded in `FORK_MANIFEST.md` § 2 and § 5.
3. If the fix requires structural divergence, it is discussed via private
   advisory before public disclosure.

## Scope Exclusions

The following are explicitly out of scope for security reports:

- Denial-of-service scenarios requiring attacker control of the chain
  (e.g., Bittensor chain halts) — these are documented operational risks.
- Third-party dependency issues where an upstream fix exists and we have not
  yet adopted it (please file a regular issue or PR instead).
- Theoretical gas-griefing where impact is negligible.
- Test-only mocks (`MockAlpha30/64`, `MockResilientOracle`, `WTAO`) — these are
  not production code.

## Credit

Security researchers who report valid vulnerabilities through proper channels
will be credited in release notes and (post-Phase 4) in any bounty program,
unless they request otherwise.
