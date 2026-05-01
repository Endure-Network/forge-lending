# Optional Liquidator Deployment Guide

The Liquidator is disabled in the default Endure local deployment. Enable it through `DeployWithOptionals.s.sol` so `DeployLocal.s.sol` and the default `addresses.json` schema stay unchanged.

## Foundry local deploy

The Liquidator depends on the VAI controller because the upstream contract reads VAI debt during liquidation checks. Start a fresh Anvil instance with the usual code-size overrides, then run:

```bash
cd packages/deploy
ENABLE_VAI=true ENABLE_LIQUIDATOR=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy \
  --code-size-limit 999999
```

The script writes `packages/deploy/addresses-optionals.json` with `liquidator`, `liquidatorImplementation`, and `protocolShareReserve` in addition to the core and VAI addresses.

## Configuration knobs

- `LIQUIDATOR_TREASURY_PERCENT` — treasury share scaled by `1e18`, default `0.05e18`.
- `LIQUIDATOR_MIN_LIQUIDATABLE_VAI` — minimum VAI debt that allows the VAI liquidation path, default `0` for local testing.
- `LIQUIDATOR_PENDING_REDEEM_CHUNK_LENGTH` — chunk size for pending redemption processing, default `10`.

## Wiring sequence

The optional helper mirrors the Venus upgradeable Liquidator pattern for local deployments:

1. Require VAI to already be wired into the Comptroller.
2. Deploy a local ProtocolShareReserve-compatible receiver.
3. Deploy the Liquidator implementation with the Unitroller, local vBNB placeholder, and WTAO address.
4. Deploy a `TransparentUpgradeableProxy` with a neutral proxy admin and initialize treasury/access-control state through the proxy.
5. Configure `minLiquidatableVAI` and `pendingRedeemChunkLength`.
6. Register the Liquidator proxy on the Comptroller via `_setLiquidatorContract`.

The Core Pool Diamond must route `actionPaused(address,uint8)` for Liquidator runtime checks and `_setActionsPaused(address[],uint8[],bool)` for BUSDLiquidator compatibility. `DiamondSelectorRouting.t.sol` covers both selectors.
