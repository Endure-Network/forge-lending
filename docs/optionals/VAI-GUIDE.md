# Optional VAI Deployment Guide

VAI is disabled in the default Endure local deployment. Enable it only through the optional deployment path so `DeployLocal.s.sol` and the default `addresses.json` schema remain unchanged.

## Foundry local deploy

Start a fresh Anvil instance with the same code-size overrides used by the default deploy, then run:

```bash
cd packages/deploy
ENABLE_VAI=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy \
  --code-size-limit 999999
```

The script writes `packages/deploy/addresses-optionals.json` with `vai`, `vaiController`, and `vaiControllerImplementation` in addition to the core addresses.

## Configuration knobs

- `VAI_MINT_RATE` — collateral value basis points available for VAI minting, default `5000`.
- `VAI_MINT_CAP` — global VAI supply cap, default `1000000e18`.
- `VAI_RECEIVER` — stability-fee receiver, default deployer.
- `VAI_TREASURY_GUARDIAN` — VAI treasury guardian, default deployer.
- `VAI_TREASURY_ADDRESS` — VAI mint-fee treasury, default deployer.
- `VAI_TREASURY_PERCENT` — mint fee percentage scaled by `1e18`, default `0`.
- `VAI_BASE_RATE` — base stability fee scaled by `1e18`, default `0`.
- `VAI_FLOAT_RATE` — floating stability fee scaled by `1e18`, default `0`.

## Wiring sequence

The optional helper mirrors Venus’ manual proxy flow:

1. Deploy legacy `VAI` bytecode with the current `chainid` constructor argument.
2. Deploy `VAIUnitroller` and `VAIController` implementation.
3. Call `_setPendingImplementation()` on the VAI proxy, then `_become()` on the implementation.
4. Initialize through the proxy.
5. Grant the VAI proxy `rely()` authority on the VAI token.
6. Set VAI token, access control, Comptroller, Comptroller VAIController, mint rate, receiver, treasury data, stability rates, mint cap, and a local oracle price for VAI.

The Core Pool Diamond must route `_setVAIController`, `_setVAIMintRate`, and `setMintedVAIOf`; the selector-routing test covers those selectors because mint/repay depends on them at runtime.
