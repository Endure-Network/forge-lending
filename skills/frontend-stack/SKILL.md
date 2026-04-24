---
name: frontend-stack
description: "Use for all Endure TypeScript off-chain work — SDK, frontend, keeper bot. Triggers on mentions of SDK, frontend, dashboard, keeper, bot, liquidator, TypeScript, wagmi, viem, RainbowKit, shadcn, shadcn/ui, Tailwind, Next.js, App Router, Recharts, moonwell-sdk, @moonwell-fi/moonwell-sdk, aave/interface, ABI translation, minimal dashboard, production frontend, netuid selector, hotkey display, tempo-lock countdown, chain 945, chain 964, Subtensor EVM chain config, user position, health factor UI, liquidation dashboard, preview deployment."
---

# Endure Frontend / Off-Chain Stack — Reference

Endure's off-chain stack is TypeScript end-to-end: SDK, frontend, and keeper bot. This skill documents the stack, the two-phase frontend approach, and the patterns that keep each package cohesive.

## The stack

| Concern | Tool | Rationale |
|---|---|---|
| Language | TypeScript | Unified off-chain language; type generation from contract ABIs |
| Runtime (packages/sdk, packages/keeper) | Node 20 LTS | Stable, wagmi/viem well-supported |
| Package manager | pnpm (workspace) | Monorepo-friendly, fast |
| Framework (frontend) | Next.js App Router | Modern React, good DX, easy preview deploys |
| Styling | Tailwind CSS + shadcn/ui | Fast iteration, accessible defaults, no design system overhead |
| Wallet | RainbowKit | Wallet connect UX without reinventing |
| Contract interaction | viem + wagmi v2 | Typed contract calls, React hooks, generated types |
| Charts | Recharts | Simple, React-native, good enough for MVP |
| Contract data | `@moonwell-fi/moonwell-sdk` (MIT) + Endure SDK wrapper | Official SDK + Endure-specific extensions |
| Type generation | wagmi CLI | ABIs → TypeScript types automatically |
| Testing (SDK/keeper) | Vitest | Fast, native TS |
| E2E (frontend) | Playwright | Standard for Next.js apps |

## Package structure

```
packages/
├── sdk/
│   ├── src/
│   │   ├── client.ts          # createEndureClient factory
│   │   ├── chains.ts          # Subtensor EVM chain configs
│   │   ├── actions/           # supply, borrow, repay, close, liquidate
│   │   ├── queries/           # getMarkets, getUserPosition, getAlphaPrice
│   │   ├── types.ts           # Re-exports + Endure-specific types
│   │   └── index.ts
│   ├── wagmi.config.ts        # wagmi CLI config; generates types from ABIs
│   └── package.json
│
├── frontend/
│   ├── app/                   # Next.js App Router
│   │   ├── layout.tsx
│   │   ├── page.tsx           # Markets overview
│   │   ├── markets/[id]/      # Market detail (supply/borrow/redeem)
│   │   ├── positions/         # User positions + HF
│   │   └── liquidations/      # Read-only liquidatable accounts
│   ├── components/
│   │   ├── ui/                # shadcn/ui primitives
│   │   ├── wallet/            # RainbowKit integration
│   │   ├── forms/             # Supply/borrow/repay/close forms
│   │   └── bittensor/         # Netuid selector, hotkey display, tempo-lock countdown
│   ├── lib/
│   │   └── sdk.ts             # Thin wrapper around packages/sdk
│   └── package.json
│
└── keeper/
    ├── src/
    │   ├── index.ts           # Main loop
    │   ├── monitor.ts         # HF scanning via getAccountLiquidity
    │   ├── liquidator.ts      # Liquidation execution
    │   └── mev.ts             # MEV-resistance (Phase 4)
    └── package.json
```

## SDK integration pattern — wrap moonwell-sdk, don't replace

`@moonwell-fi/moonwell-sdk` does most of what Endure needs. Wrap it; don't reimplement.

```typescript
// packages/sdk/src/client.ts
import { createMoonwellClient } from '@moonwell-fi/moonwell-sdk';
import { subtensorTestnet, subtensorFinney } from './chains';

export function createEndureClient(opts: { chainId: 945 | 964; rpcUrl: string }) {
  const moonwell = createMoonwellClient({
    networks: {
      [opts.chainId]: { rpcUrls: [opts.rpcUrl] },
    },
  });

  return {
    ...moonwell,
    // Endure-specific extensions
    getAlphaPrice: (netuid: number) => readAlphaPrice(moonwell, netuid),
    getTempoLockStatus: (user: `0x${string}`, netuid: number) => readTempoLock(moonwell, user, netuid),
    getSubnetReserves: (netuid: number) => readSubnetReserves(moonwell, netuid),
  };
}
```

The wrapping pattern keeps upstream SDK improvements available (bumping `@moonwell-fi/moonwell-sdk` picks up their new features) while letting Endure add Bittensor-specific helpers without forking their repo.

## wagmi + viem chain config for Subtensor EVM

Define chains once, import everywhere:

```typescript
// packages/sdk/src/chains.ts
import { defineChain } from 'viem';

export const subtensorFinney = defineChain({
  id: 964,
  name: 'Bittensor Finney',
  nativeCurrency: { name: 'TAO', symbol: 'TAO', decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_FINNEY_RPC!] },
  },
  blockExplorers: {
    default: { name: 'Taostats', url: 'https://evm.taostats.io' },
  },
});

export const subtensorTestnet = defineChain({
  id: 945,
  name: 'Bittensor EVM Testnet',
  nativeCurrency: { name: 'tTAO', symbol: 'tTAO', decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_TESTNET_RPC!] },
  },
  blockExplorers: {
    default: { name: 'Taostats Testnet', url: 'https://evm-testnet.taostats.io' },
  },
  testnet: true,
});
```

Use these in `wagmi` provider setup at the frontend root. Never hardcode chain IDs in components.

## Two-phase frontend — what's in each phase

### Phase 1 — Minimal dashboard (NOT the production UI)

**Purpose**: human-operable interface against testnet. Internal tool. Partner demos. SDK-gap discovery.

**In scope**:
- 4-6 functional screens using shadcn defaults + Tailwind
- Wallet connect (RainbowKit pointed at chain 945)
- Markets table (name, supply APY, borrow APY, caps, user balance)
- Market detail with supply/redeem/borrow/repay forms
- Positions view with HF display
- Liquidations view (read-only)
- All contract interactions via `packages/sdk` — no direct wagmi calls in components
- Deployed to preview URL (Vercel / IPFS)

**Explicitly out of scope**:
- Custom branding, design system, or visual polish
- Marketing pages, landing page, `/about`, `/docs`, footer content
- SEO optimization, Open Graph tags, sitemap
- Responsive mobile layout (desktop-first; mobile in Phase 4)
- Analytics, event tracking, user telemetry
- Accessibility audit (basic a11y via shadcn is fine; WCAG compliance is Phase 4)
- Error boundary polish (console-log errors fine for MVP)
- Loading skeletons, optimistic updates, fancy transitions
- i18n or dark/light mode switching

The minimal dashboard looks brutalist. That's correct. If it looks "done," the scope crept.

### Phase 4 — Production frontend (aave/interface fork)

**Purpose**: launch-quality UX.

**Approach**:
1. Fork `aave/interface` at a pinned commit (BSD-3 licensed)
2. Port the validated flows from Phase 1's minimal dashboard
3. Adapt the ABI layer from Aave V3's `IPool`/`AToken` calls to Moonwell's `IComptroller`/`IMToken`
4. Strip multi-borrow UX (see below)
5. Add Bittensor affordances already validated in the minimal dashboard
6. Apply brand, polish, responsive, accessibility

**What to strip from aave/interface**:

| Feature | Reason |
|---|---|
| Market picker for borrow asset | TAO is the only borrowable |
| Stable-rate vs variable-rate toggle | Moonwell has a single IRM per market |
| E-mode selector and UI | Not in Moonwell |
| Isolation-mode warnings and per-collateral debt ceiling UI | Not in Moonwell |
| Siloed-asset warnings | Not in Moonwell |
| Flash loan entry points | Not in Endure MVP |
| Cross-chain bridge widgets | Single-chain |
| GHO-specific components | Aave-specific stablecoin |

**What the ABI translation layer does**:

Aave's `IPool.supply(asset, amount, onBehalfOf, referralCode)` becomes Moonwell's `MToken.mint(amount)`. The translation layer in `packages/frontend/lib/sdk.ts` presents a consistent interface to the components:

```typescript
// Frontend components call this uniform interface
export interface LendingClient {
  supply(params: { market: Address; amount: bigint }): Promise<Hash>;
  borrow(params: { market: Address; amount: bigint }): Promise<Hash>;
  repay(params: { market: Address; amount: bigint }): Promise<Hash>;
  redeem(params: { market: Address; amount: bigint }): Promise<Hash>;
  liquidate(params: { borrower: Address; repayMarket: Address; seizeMarket: Address; amount: bigint }): Promise<Hash>;
}
```

Implementation dispatches to Moonwell's mToken ABI via `packages/sdk`. Components don't know (or care) that the backing contracts are Moonwell. This shields the UI from any future contract-layer changes.

## Key Bittensor-specific UX affordances

These emerged from the minimal dashboard phase and get refined for production. Each solves a specific Bittensor mental-model gap:

| Component | Purpose | Where it lives |
|---|---|---|
| **Netuid selector** | User picks which subnet's alpha to deposit; show subnet name, TAO/alpha price, 24h volume | Supply form, market detail |
| **Hotkey display** | User sees "your alpha is staked with hotkey `5ABC…XYZ`" — reinforces that alpha is real substrate state, not an ERC20 | Positions view, supply confirmation modal |
| **Tempo-lock countdown** | "Your 100 alpha_64 is stake-locked for 47m 12s" — prevents confusion when withdrawal reverts | Positions view, redeem form |
| **Alpha price source tooltip** | "Price from subnet AMM reserves · last updated 2 blocks ago · EnduOracle" | Next to any alpha price display |
| **Oracle circuit-breaker banner** | Prominent banner when oracle has halted new borrows due to deviation | Top of all screens when active |
| **Liquidation preview** | Show the `alpha → TAO` AMM slippage preview BEFORE user confirms liquidation | Liquidation form |
| **HF trajectory** | Small sparkline of HF over last 24h — catches trending-unhealthy positions early | Positions view |

## Keeper bot patterns

`packages/keeper` is a TypeScript process (Node/Bun) that watches for liquidatable accounts and executes liquidations. Stays deliberately simple.

Core loop:
```typescript
while (true) {
  const accounts = await getAllBorrowers(client);
  for (const account of accounts) {
    const { err, liquidity, shortfall } = await comptroller.read.getAccountLiquidity([account]);
    if (shortfall > 0n) {
      await attemptLiquidation(client, account);
    }
  }
  await sleep(BLOCK_TIME_MS);
}
```

Phase 4 adds:
- MEV-resistance: submit via private mempool where available, or randomize timing within a block
- Bounty optimization: compute expected seize value across all markets, pick the most profitable pair
- Gas budgeting: skip liquidations where gas > bounty
- Observability: emit metrics (successful/failed/skipped liquidations, HF distribution)
- Rate-limit handling: honor `StakingOperationRateLimiter` errors gracefully

Keep the keeper stateless. State lives in contracts; keeper is a read-and-act loop.

## Preview deployments during Phase 1-3

Frontend gets deployed to a preview URL on every commit. Any of:
- Vercel: simplest, works out of the box with Next.js
- Cloudflare Pages: cheap, fast, Next.js-compatible
- IPFS via Fleek: decentralized posture, matches DeFi norms (aave/interface ships this way)

MVP recommendation: **Vercel for Phases 1-3**, switch to IPFS for Phase 4 launch. Vercel's DX accelerates iteration; IPFS's decentralization matters for the real launch.

## Shared types via wagmi CLI

Every package in the monorepo imports types from `packages/sdk`. Generation lives in `packages/sdk/wagmi.config.ts`:

```typescript
import { defineConfig } from '@wagmi/cli';
import { foundry } from '@wagmi/cli/plugins';

export default defineConfig({
  out: 'src/generated.ts',
  plugins: [
    foundry({
      project: '../contracts',
      include: ['Comptroller.json', 'MErc20.json', 'MAlpha.json', 'BittensorStakeAdapter.json', 'EnduOracle.json'],
    }),
  ],
});
```

Run `pnpm --filter sdk generate` whenever contract ABIs change. Generated types flow to frontend and keeper via workspace imports.

## What NOT to do

| Don't | Why |
|---|---|
| Build a branded UI before Phase 4 | Scope creep; delays real product validation |
| Add SEO, Open Graph, marketing pages to the minimal dashboard | Not users yet; distraction |
| Use class components or legacy React patterns | App Router is function-components + hooks |
| Hardcode contract addresses in components | Use SDK; addresses live in one place |
| Hardcode chain IDs in components | Use exported chain configs |
| Call viem/wagmi directly from components | Go through `packages/sdk`; keeps the translation layer intact |
| Fork aave/interface in Phase 1 | Production UI before validated flows is premature |
| Write Python bots in Phase 4+ | Off-chain is TypeScript; Python is for the SN30 risk oracle, a separate concern |
| Build mobile-responsive before desktop flows are validated | Desktop-first, mobile in Phase 4 |
| Add analytics or telemetry in minimal dashboard | Not users yet; Phase 4 |
| Add Redux/Zustand/global state management early | wagmi's React Query integration covers 95% of needs; don't prematurely abstract |

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Importing from `@moonwell-fi/moonwell-sdk` directly in frontend components | Couples frontend to upstream SDK surface; harder to add Endure helpers | Always go through `packages/sdk` |
| Using `bigint` literals without `n` suffix | Type errors on arithmetic | `100n * 10n**18n` not `100 * 10**18` |
| Treating on-chain amounts as `number` | Loss of precision beyond 2^53 | Always `bigint` for on-chain values |
| Hardcoding RPC URLs | Breaks between testnet/mainnet | Env vars; exported chain configs |
| Forgetting to handle `StakeLocked` revert in redeem form | User gets cryptic "reverted" error | Parse revert reason; show tempo countdown |
| Confusing H160 (EVM address) with SS58 (substrate address) in UI | User sees wrong address format | Always show H160 in EVM contexts; show SS58 mirror only when relevant (e.g., explaining where their alpha actually lives on substrate) |
| Showing USD prices everywhere | Implies USD oracle exists; it doesn't under TAO-only | TAO-denominate all prices; USD conversion (if shown) is informational only |
| Displaying supply/borrow APY without APR context | Users conflate the two | Label explicitly; show both where useful |
| Optimistic UI updates without rollback on tx failure | UI shows success, chain didn't | Wait for confirmation; show pending states |
