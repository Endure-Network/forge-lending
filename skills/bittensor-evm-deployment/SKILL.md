---
name: bittensor-evm-deployment
description: "Use when deploying contracts to Subtensor EVM, funding deployer accounts, configuring RPC endpoints, verifying contracts, or working with the H160-mirror SS58 gas payment model. Triggers on mentions of Finney, Subtensor EVM, chain 964, chain 945, devnet, btcli wallet transfer, foundry deploy Bittensor, forge script Bittensor, deploy to Bittensor, RPC Bittensor, Subtensor RPC, contract verification Bittensor, gas funding H160, mirror SS58 funding."
---

# Bittensor EVM Deployment — Reference

Subtensor EVM is a Frontier pallet running inside the Substrate runtime. EVM deployment is standard — any `forge script`, `hardhat deploy`, or raw `eth_sendRawTransaction` works. The nuances are:

1. Gas is paid in TAO via the deployer's H160-derived SS58 (funding is a substrate-side operation, not EVM)
2. Block time is 12s (substrate block time), significantly slower than L2 norms
3. Not all EVM opcodes are supported by default; verify `PUSH0` before compiling with Solidity ≥ 0.8.20
4. Chain has historical halt incidents; deployment scripts should be resumable

## Chain identifiers

| Environment | Chain ID | Block time | Purpose |
|---|---|---|---|
| Finney mainnet | **964** | ~12s | Production |
| Subtensor EVM testnet | **945** | ~12s | Staging, Phase 1/3 testing |
| Devnet | (ask, varies) | ~12s | PR testing including #2478 |
| Local (subtensor node) | varies | configurable | Phase 2 development |
| Local Anvil | 31337 | 12s or instant | Phase 0 |

## RPC endpoints

Verify endpoints directly before use — these rotate. Authoritative list: `docs.learnbittensor.org/evm-tutorials`.

| Environment | Current public endpoints (verify) |
|---|---|
| Finney mainnet | `https://lite.sub.latent.to`, `https://evm.taostats.io`, OTF-hosted |
| Testnet (chain 945) | `https://test.finney.opentensor.ai`, testnet-equivalent endpoints |
| Devnet | Request from OTF / Bittensor Discord |

**Use a private RPC for production**. OTF-provided public RPCs rate-limit at 1 request/second per IP.

## Solidity and EVM compatibility

- Solidity **0.8.19** is the safe default (Moonwell v2's pinned version)
- Solidity **0.8.20+** uses `PUSH0` — verify Subtensor runtime supports it before upgrading. TaoFi has deployed Uniswap V3 clean on Subtensor EVM which implies Shanghai support, but confirm directly in the `EVMConfig` of the runtime you're deploying against.
- `evm_version = "shanghai"` in `foundry.toml` should work on current Finney; set explicitly to avoid surprises
- Standard opcodes all present; no known exotic restrictions

Confirmation checklist for a new deployment target:
```
cast code 0x0000000000000000000000000000000000000805 --rpc-url $RPC  # precompile exists
cast block latest --rpc-url $RPC                                     # block time, base fee
cast estimate-gas <simple-deploy> --rpc-url $RPC                     # gas estimation works
```

## Funding a deployer

The deployer's gas balance lives at `Balances::Account[SS58_mirror_of_H160_deployer]`. Funding is a substrate transfer, not an EVM transfer.

### Manual flow (Phase 1 acceptable)

1. Generate deployer H160 + private key (standard EVM keypair)
2. Compute mirror SS58: `ss58_encode(blake2_256(b"evm:" + bytes.fromhex(h160_hex)), 42)`
   - Use `bittensor` Python SDK: `bittensor.utils.evm.h160_to_ss58(h160)` or equivalent
   - Or `polkadot-js` utilities
3. Transfer TAO to the SS58:
   ```bash
   btcli wallet transfer --dest <SS58_mirror> --amount <tao> --network <testnet|finney>
   ```
4. Verify balance visible from EVM:
   ```bash
   cast balance <H160_deployer> --rpc-url $RPC
   ```

Budget: ~0.1 TAO for a full Moonwell v2 deploy (hundreds of contracts). ~0.01 TAO for a single market add. Check current gas prices on the target network.

### Automated flow (Phase 2+)

Write a utility in `packages/deploy/src/fund-deployer.ts` that:
1. Takes H160 deployer address and target TAO amount
2. Computes mirror SS58 via `@polkadot/util-crypto` `blake2AsHex`
3. Connects to substrate RPC via `@polkadot/api`
4. Submits `balances.transferKeepAlive` from a funded coldkey (mnemonic in env)
5. Waits for inclusion
6. Verifies EVM-side balance via `viem.getBalance`

## Contract verification

Subtensor EVM explorers (verify current):

| Explorer | Networks |
|---|---|
| `evm.taostats.io` | Finney, testnet |
| `bittensor.scan.caldera.xyz` | Finney |

Verification flow via Foundry:
```bash
forge verify-contract --chain 964 \
  --etherscan-api-key $EXPLORER_API_KEY \
  --verifier etherscan \
  --verifier-url <explorer-api-url> \
  <contract-address> <contract-path>:<contract-name>
```

Some explorers accept `--verifier blockscout` with no API key. Check explorer docs at deploy time.

## Resumable deployment script pattern

Chain halts (July 2024, May 2025) and RPC failures happen. Deploy scripts must tolerate mid-deploy interruption.

Pattern for `packages/deploy/`:

```solidity
// forge script, not a one-shot broadcast
contract DeployMarket is Script {
    // Persist deployed addresses to JSON between runs
    function run() external {
        Addresses a = new Addresses("broadcast/endure-markets.json");
        vm.startBroadcast();
        if (!a.has("Comptroller")) a.set("Comptroller", address(new Comptroller()));
        if (!a.has("Unitroller")) a.set("Unitroller", address(new Unitroller()));
        // ...
        vm.stopBroadcast();
    }
}
```

Moonwell v2's `mip-b00.sol`-style proposal framework does this — copy that pattern directly.

## Common deployment pitfalls

| Pitfall | Fix |
|---|---|
| Deployer H160 has no balance | Fund SS58 mirror via btcli, not via any Ethereum bridge |
| `forge script` says "chain id mismatch" | Explicit `--chain 964` flag; foundry caches chainId from first RPC hit |
| Precompile calls revert with no reason | Verify precompile exists at target address on this network (`cast code 0x...0805`) |
| Verification fails with "bytecode doesn't match" | Match `evm_version` and optimizer settings exactly to what compiled the broadcast |
| Deploy script mid-way through chain halt | Resumable pattern above; never use `deal()`-style assumptions in production scripts |
| RPC rate-limited during large deploy | Use private RPC; add retries with backoff in deploy utilities |
| `cast send` hangs forever | 12s block time; `--gas-limit` explicit; consider `--async` for scripted flows |

## Environment configuration for Endure

Proposed `foundry.toml` profiles:

```toml
[profile.default]
solc_version = "0.8.19"
evm_version = "shanghai"
optimizer = true
optimizer_runs = 200

[rpc_endpoints]
localhost = "http://localhost:8545"
subtensor_testnet = "${SUBTENSOR_TESTNET_RPC}"
subtensor_finney = "${SUBTENSOR_FINNEY_RPC}"
subtensor_devnet = "${SUBTENSOR_DEVNET_RPC}"

[etherscan]
subtensor_testnet = { key = "${TAOSTATS_API_KEY}", url = "https://evm-testnet.taostats.io/api" }
subtensor_finney = { key = "${TAOSTATS_API_KEY}", url = "https://evm.taostats.io/api" }
```

Endpoints and API URLs above are illustrative — verify at deploy time.

## Observability during deploy

- Watch Subtensor block production: `curl -s "$RPC" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' -H 'content-type: application/json'`
- During halts, `eth_blockNumber` stops advancing. Abort and resume after halt resolution.
- For Bittensor-wide status: OTF Discord `#announcements`, `@opentensorfdn` X account
