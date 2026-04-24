---
name: bittensor-precompiles
description: "Use whenever writing Solidity that touches Bittensor EVM precompiles — staking, alpha token custody, H160↔SS58 conversions, metagraph reads, subnet AMM reads. Triggers on mentions of 0x805, 0x801, 0x800, 0x802, 0x803, 0x807, StakingV2, transferStake, transferStakeFrom, approve (in precompile context), alpha tokens, staking precompile, AlphaPrecompile, MetagraphPrecompile, NeuronPrecompile, SubnetPrecompile, StorageQueryPrecompile, precompile, substrate, netuid, hotkey, coldkey, removeStake, addStake, moveStake, swapStake, stake lock, tempo lock, StakingOperationRateLimiter, RAO, H160, SS58, Blake2, coldkey mirror, evm mirror. Also triggers when writing custody hooks (doTransferIn/Out) for any Endure MAlpha market, when implementing oracle adapters that read subnet AMM state, and when writing keeper bots that monitor staking positions."
---

# Bittensor EVM Precompiles — Reference

Bittensor EVM is Frontier-based, running on Subtensor. Native Bittensor state (stake positions, subnet AMMs, neuron metadata) lives in substrate pallets. EVM contracts access it through precompiles at fixed addresses.

## Precompile addresses (as of April 2026)

| Address | Name | Purpose |
|---|---|---|
| `0x0000000000000000000000000000000000000800` | Ed25519Verify | Verify Ed25519 signatures |
| `0x0000000000000000000000000000000000000801` | StakingPrecompile (V1) | **Deprecated** — kept for backwards compat |
| `0x0000000000000000000000000000000000000802` | MetagraphPrecompile | Read neuron/subnet metadata |
| `0x0000000000000000000000000000000000000803` | SubnetPrecompile | Subnet-level queries |
| `0x0000000000000000000000000000000000000804` | NeuronPrecompile | Neuron management |
| `0x0000000000000000000000000000000000000805` | **StakingPrecompileV2** | **Primary for Endure** |
| `0x0000000000000000000000000000000000000807` | StorageQueryPrecompile | Raw SCALE storage reads — **deprecating (issue #2455), avoid** |
| `0x0000000000000000000000000000000000000400` | Sha3FIPS256 | SHA3-256 FIPS variant |
| `0x0000000000000000000000000000000000000401` | ECRecoverPublicKey | Recover pubkey from signature |

Standard Ethereum precompiles (0x01-0x09) also present.

**Canonical source**: `opentensor/subtensor/precompiles/src/solidity/*.abi`. Pin to a specific commit in Endure and version-gate.

## StakingV2 (0x805) — the one Endure actually uses

### Functions currently live on Finney mainnet

```solidity
interface IStakingV2 {
  // Write operations — mutate substrate stake state
  function addStake(bytes32 hotkey, uint256 netuid, uint256 amount) external;
  function removeStake(bytes32 hotkey, uint256 netuid, uint256 amount) external;
  function moveStake(
    bytes32 originHotkey, bytes32 destHotkey,
    uint256 originNetuid, uint256 destNetuid,
    uint256 alphaAmount
  ) external;
  function transferStake(
    bytes32 destColdkey,
    bytes32 hotkey,
    uint256 originNetuid, uint256 destNetuid,
    uint256 alphaAmount
  ) external;

  // Read operations
  function getStake(bytes32 hotkey, bytes32 coldkey, uint256 netuid) external view returns (uint256);
  function getTotalColdkeyStake(bytes32 coldkey) external view returns (uint256);
  function getTotalHotkeyStake(bytes32 hotkey) external view returns (uint256);

  // Proxy management
  function addProxy(bytes32 delegate) external;
  function removeProxy(bytes32 delegate) external;
}
```

### Functions on `devnet-ready`, not yet Finney (PR #2478)

```solidity
  function approve(address spender, uint256 netuid, uint256 amount) external;
  function transferStakeFrom(address from, bytes32 hotkey, uint256 netuid, uint256 amount) external;
  function allowance(address owner, address spender, uint256 netuid) external view returns (uint256);
  function increaseAllowance(address spender, uint256 netuid, uint256 added) external;
  function decreaseAllowance(address spender, uint256 netuid, uint256 subtracted) external;
```

**Critical**: atomic deposit from user to Endure vault requires `transferStakeFrom`. Do not assume mainnet availability until PR #2478 promotes from devnet. Endure Phase 3 (testnet) can target devnet-ready; Phase 4 mainnet deploy gated on promotion.

### Functions that DO NOT exist on the precompile

- `swapStake` — exists as substrate extrinsic, NOT exposed on 0x805. If cross-subnet alpha rotation is ever needed, use `moveStake` with same hotkey and different netuids.
- `removeStakeLimit` — substrate-side `remove_stake_limit` exists with price protection, but no EVM wrapper. Liquidation slippage must be guarded post-unstake via balance-delta check + revert until this lands on the precompile.
- `removeStakeFrom` — no allowance-based unstake. Not needed for Endure because the vault unstakes its own alpha at liquidation.

## The H160 ↔ SS58 mirror (non-negotiable)

Every H160 deterministically maps to a substrate SS58:

```
SS58_mirror = Blake2b-256("evm:" || H160_bytes)   // then SS58-encode with prefix 42
```

Properties:

- **One-way**: given H160, the SS58 is computable. Given arbitrary SS58, you cannot derive the H160.
- **No registration**: the SS58 exists the moment the H160 exists. Deploying a contract creates its SS58 implicitly.
- **Unified storage**: the SS58's substrate balance (`Balances::Account`, `Alpha[(hotkey, coldkey, netuid)]`) IS the H160's EVM view. One ledger.
- **Contract is coldkey**: when an EVM contract calls `addStake` via `0x805`, the precompile uses the contract's own H160-derived SS58 as the coldkey. `msg.sender` (the EOA that called the contract) is invisible to substrate.

### Reference Solidity utility

```solidity
library SS58 {
  // Returns the SS58 mirror account ID (32 bytes, no prefix byte) for an H160.
  function mirrorOf(address h160) internal pure returns (bytes32) {
    bytes memory prefixed = abi.encodePacked(bytes4(0x65766d3a), h160); // "evm:" || h160
    return blake2b256(prefixed); // requires Blake2 precompile or library
  }
}
```

Note: Solidity has no native Blake2b. Use a library like `@subtensor-contracts/solidity-blake2` or equivalent. Verify hash output matches substrate-side before trusting.

## Decimal conversion — 9 (RAO) ↔ 18 (EVM)

Substrate denominates everything in RAO: 1 TAO = 10^9 RAO. EVM typically uses 18 decimals. Every precompile amount argument is RAO.

```solidity
uint256 constant RAO_TO_WEI = 10**9;

function raoFromWei(uint256 weiAmount) internal pure returns (uint256) {
  return weiAmount / RAO_TO_WEI;
}

function weiFromRao(uint256 raoAmount) internal pure returns (uint256) {
  return raoAmount * RAO_TO_WEI;
}
```

### Conversion hazards

- **Truncation on wei→RAO**: any wei amount not cleanly divisible by 10^9 loses dust. Document and handle:
  - For deposits, round DOWN (user gets what they paid in; residual stays in vault balance).
  - For withdrawals, round DOWN on the user side, track dust as protocol revenue.
- **Overflow on RAO→wei**: RAO amounts up to ~2^64 fit cleanly in uint256 * 10^9.
- **Always do conversion at the precompile boundary**, never in the middle of Moonwell's 18-decimal accounting. Centralize in `BittensorStakeAdapter`.

Property-based fuzz test: `raoFromWei(weiFromRao(x)) == x` for all `x < 2^64`.

## Tempo stake lock (PR #1731, live on Finney)

After any stake-adding operation (`addStake`, `moveStake` into a destination, `transferStake` to own coldkey), the triple `(hotkey, coldkey, netuid)` is locked for the destination subnet's **tempo** (~360 blocks / ~72 minutes).

- **Removal operations check the lock first** and revert with `StakeLocked`.
- **Exception**: `transfer_stake` with a different destination coldkey does NOT apply a lock to the destination (prevents griefing).
- **Implication for Endure**: a user who deposits alpha via `transferStakeFrom` cannot have that alpha liquidated out for the first ~72 minutes. HF math must account for this — if a user is barely solvent at deposit, they could be unliquidatable while the lock holds. Liquidation threshold must include a buffer; keeper should surface lock status explicitly.

## Staking operation rate limit

Storage: `StakingOperationRateLimiter: NMap ((hotkey, coldkey, netuid) → bool)` in `pallets/subtensor/src/lib.rs`.

- **1 operation per block (~12s)** per `(hotkey, coldkey, netuid)` triple
- Applies to `add_stake`, `remove_stake`, `move_stake`, `transfer_stake` and their `*_limit` variants
- Error: `StakingOperationRateLimitExceeded`
- **Cross-netuid operations are independent** — separate triples, no serialization
- **Single-hotkey MVP is fine**: 5 ops/minute on same triple is plenty for early volumes

Query via Polkadot.js: `substrate.query('SubtensorModule', 'StakingOperationRateLimiter', [hotkey, coldkey, netuid])`.

Obsolete info to ignore: the "1 per 360 blocks per (hotkey, coldkey) pair" figure from older docs (taostats FAQ etc.) is pre-dTAO and wrong.

## Staking fees

- **Stake/unstake swap fee**: 0.05% of transacted liquidity on subnet AMMs, applied by substrate
- **Minimum operation amount**: 500,000 RAO (0.0005 TAO)
- **Extrinsic weight fee**: paid in TAO from the origin's free balance

For Endure: factor 0.05% into expected-return calculations on deposit and liquidation. Minimum amount rules out dust positions.

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Passing 18-decimal amount to precompile | Overflow or revert | Convert to RAO at adapter boundary |
| Treating `0x805.addStake` caller as EOA | Wrong coldkey, stake credited to contract unexpectedly | `msg.sender` from user is invisible; contract IS the coldkey |
| Hardcoding precompile addresses across versions | Breaks on precompile lifecycle events (issue #2455) | Use typed Solidity interfaces wrapped in upgradeable adapter |
| Assuming `removeStake` has slippage protection | Liquidation can get poor prices in thin AMMs | Post-unstake balance-delta guard + revert |
| Assuming `transferStakeFrom` is on mainnet | Atomic deposit fails on Finney | Gate Phase 4 mainnet deploy on PR #2478 promotion |
| Ignoring tempo lock in HF math | Unliquidatable positions during lock window | Liquidation threshold buffer + explicit lock surfacing |
| Relying on `StorageQueryPrecompile` for reads | Silently wrong on substrate layout changes | Use typed precompiles (AlphaPrecompile/MetagraphPrecompile) |
| Attempting alpha→alpha swap via non-existent `swapStake` | Call reverts, swallowed by EVM | Use `moveStake` same-hotkey + netuid swap if truly needed, else route via TAO |

## Verification before shipping

When writing new Solidity touching precompiles:

1. Cross-check function selectors against `opentensor/subtensor/precompiles/src/solidity/*.abi` at a pinned commit
2. For every write-path, test rate-limit behavior under rapid successive calls
3. For every read-path, test behavior when the underlying subnet is paused/dereg'd
4. For every user-facing error, test the revert reason is human-readable and actionable
5. Never trust price/reserve reads that aren't from typed precompiles
