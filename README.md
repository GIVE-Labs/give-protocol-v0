# GIVE Protocol — MVP (Three‑Vaults)

A production‑oriented MVP for no‑loss donations using three ERC‑4626 vaults with fixed donation splits (50%, 75%, 100%), a single simple adapter, an NGO allowlist, and a donation payer. Withdrawals are always open. This branch removes the earlier epoch/Merkle/decoder architecture to ship a tight, auditable core.

## Overview

- Three vaults (instances of `SimpleVault4626Upgradeable`) with immutable donation splits at initialization:
  - GIVE‑50: 50% of harvested yield donated
  - GIVE‑75: 75% donated
  - GIVE‑100: 100% donated
- Harvest has no epochs: the vault computes realized yield from `totalAssets` versus a rolling baseline, skims protocol fee first, then donates split to the configured NGO, leaving the remainder in the vault (share price increases).
- Withdrawals/redeems cannot be paused. Deposits/mints can be paused by the Guardian and during a short harvest window.
- One NGO per vault at a time, switched via a 48h delay; harvest must pass `ngo == currentNGO`.
- Single adapter (no swaps/callbacks). The MVP includes a holding adapter; an Aave V3.1 adapter can be added later.

## Contracts

- Vault
  - `src/vault/SimpleVault4626Upgradeable.sol` (UUPS upgradeable)
    - Fixed `donationPercentBps` (5000/7500/10000) set at init.
    - Tracks `assetsAtLastHarvest`, `inflowSinceLast`, `outflowSinceLast` to compute harvested yield.
    - `harvest(ngo)` → fee first (≤ 1.5%), donation via `DonationPayer`, remainder retained. Opens short harvest window (deposits paused only).
    - `currentNGO` set via queue + 48h delay; must be allow‑listed in `NGORegistrySimple`.
    - Guardian can `pauseDeposits(bool)` and `emergencyUnwind(maxLossBps)`. Withdrawals remain open.
    - Uses exact approvals and resets to zero after use.

- Adapter
  - `src/adapter/SimpleHoldingAdapter.sol`
    - Holds underlying; implements `deposit/withdraw/totalAssets/emergencyUnwind`.
    - No swaps, no callbacks. Includes `setVault(address)` one‑time wiring after proxy deploy.

- NGO & Payer
  - `src/ngo/NGORegistrySimple.sol` (upgradeable): `announceAdd` → 48h → `add`; `revoke` immediate.
  - `src/ngo/DonationPayer.sol`: authorized callers (vaults) transfer donations; nonReentrant; emits `DonationPaid`.

- Treasury
  - `src/governance/TreasurySimple.sol`: receive protocol fees (pull) and allow owner sweep.

## Build & Test

Prereqs
- Foundry (forge, cast, anvil)
- Ensure dependencies are installed per `foundry.toml` remappings

Build
- `forge build`

Run tests
- `forge test -vv`  (unit tests)
- For gas report: `forge test --gas-report`
- Suggested filters:
  - `forge test --match-contract Test01_SimpleVault_Core -vv`
  - `forge test --match-contract Test02_Approvals_Unwind_NGO -vv`

Coverage (local)
- `forge coverage --report lcov` (then view with lcov tools)

## Local Runbook (Anvil)

1) Deploy components
- Deploy `TreasurySimple`, `NGORegistrySimple` (proxy), `DonationPayer`, and the holding adapter.
- Deploy 3x `SimpleVault4626Upgradeable` behind ERC1967Proxy with splits 50/75/100 and wire:
  - `adapter` (call `setVault(vault)` on the adapter after proxy deploy),
  - `treasury`, `donationPayer`, `ngoRegistry`, `owner`, `guardian`, `protocolFeeBps`, `tvlCap`, `harvestWindowBlocks`.
- Authorize vaults on `DonationPayer.setAuthorizedCaller(vault, true)`.

2) NGO lifecycle
- `NGORegistrySimple.announceAdd(ngo)` → wait 48h → `add(ngo)`.
- For each vault: `queueCurrentNGO(ngo)` → wait 48h → `switchCurrentNGO()`.

3) Deposit and harvest
- Users approve and `deposit` into the chosen vault.
- Yield accrues in the adapter (or venue). Call `harvest(currentNGO)` to:
  - Compute harvested, skim fee to Treasury, donate split via DonationPayer, retain the rest.
  - A brief harvest window opens; deposits/mints paused; withdrawals remain open.

4) Emergencies
- Guardian: `pauseDeposits(true)` and `emergencyUnwind(maxLossBps)`; verify assets at vault; resume deposits when safe.

## Deployment (Testnet → Mainnet)

- Testnet: Base Sepolia
  - Start with holding adapter; optional fork tests against Aave V3.1.
- Mainnet: Base
  - Asset: USDC (6 decimals)
  - Venue: Aave V3.1 (for SimpleAaveAdapter when added)

High‑level deployment order
1. NGORegistrySimple (UUPS proxy)
2. TreasurySimple
3. DonationPayer
4. Adapter (holding or Aave)
5. Three vaults (UUPS proxy) with splits (50/75/100)
6. Wire: authorize payer, set Guardian, set TVL caps/fees
7. Queue currentNGO → wait 48h → switch
8. Open deposits

## Security & Invariants

- Withdrawals never pausable; harvest window blocks deposits/mints only.
- Harvest conservation: `harvested == fee + donated + retained`.
- currentNGO must be allow‑listed and selected via 48h delay.
- Approval hygiene: exact approvals set and reset to zero.
- Guardian powers limited to deposit pause + emergencyUnwind.
- UUPS upgradeability gated by owner.

## File Map

- Vault: `src/vault/SimpleVault4626Upgradeable.sol`
- Adapter: `src/adapter/SimpleHoldingAdapter.sol`
- NGO: `src/ngo/NGORegistrySimple.sol`
- Payer: `src/ngo/DonationPayer.sol`
- Treasury: `src/governance/TreasurySimple.sol`
- Tests: `test/unit/*.t.sol`

## Future Work

- Add `SimpleAaveAdapter` for Aave V3.1 on Base and fork tests.
- Add invariants/fuzz suites for principal conservation and approval hygiene across random sequences.
- Monitoring dashboards for events (Harvest, DonationPaid, DepositsPaused, CurrentNGOSet/Switch, EmergencyUnwind).

---

This MVP is intentionally small and auditable. It preserves the core “withdrawals always open” guarantee and routes only realized yield to vetted NGOs with simple, observable mechanics.

