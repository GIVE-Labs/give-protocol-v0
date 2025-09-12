# AGENTS.md — GIVE Protocol (MVP, Three‑Vaults)

**Owner:** Project Manager
**Audience:** Solidity engineers, QA, DevOps, Security, AI coding agents
**Status:** Authoritative MVP build brief (production‑ready)
**Architecture:** Three fixed‑split ERC‑4626 vaults + simple adapter + NGO allowlist + donation payer
**Scope:** Single chain, single underlying asset per vault, one adapter (no swaps)

---

## 1) Mission & Scope

Ship a no‑loss donation MVP with three ERC‑4626 vaults offering fixed donation splits:
- GIVE‑50 (50% yield donated)
- GIVE‑75 (75% yield donated)
- GIVE‑100 (100% yield donated)

Users deposit into the vault matching their preference. Only harvested yield is donated to allow‑listed NGOs. Withdrawals can never be paused.

Out of scope (MVP): per‑user donation choices, epochs/Merkle, strategy rotation, cross‑chain, incentives token, decoders/sanitizers, complex oracle/exposure math, multiple adapters.

---

## 2) Quick Decisions (locked)

- Venue: Aave V3.1 on Base mainnet (low gas, blue‑chip).
- Asset: USDC (6 decimals) in prod; tests also cover WETH (18).
- Testnet: Base Sepolia with mock/holding adapter first; optional fork tests vs Aave V3.
- Per‑vault NGO: one currentNGO per vault set by Owner with 48h delay; `harvest(ngo)` requires `ngo == currentNGO`.
- Proxies: Proxied (UUPS) for vaults and NGORegistry. DonationPayer and Adapter are non‑upgradeable. Add `postUpgrade()` smoke checks and storage gaps; ship a tiny VaultMigratorV2 later as fallback.

---

## 3) Contracts (MVP)

1) SimpleVault4626Upgradeable (x3: GIVE‑50/75/100)
   - ERC‑4626 (OZ) with fixed `donationPercentBps` (5000/7500/10000; set at init; not mutable).
   - Single `ISimpleAdapter` venue, `treasury`, `donationPayer`, `ngoRegistry`.
   - Harvest (no epochs): computes `harvested = max(totalAssetsNow − (assetsAtLastHarvest + inflow − outflow), 0)`; fee first, then donation; retained stays in vault (share price ↑).
   - Withdrawals/redeems never pausable. Deposits/mints pausable (guardian) and during a short harvest window.
   - `currentNGO` queued with 48h delay (must be allow‑listed) and enforced in `harvest(ngo)`.
   - TVL cap; exact approvals to DonationPayer; adapter approvals set to exact then zero.
   - Guardian: `pauseDeposits(bool)` and `emergencyUnwind(maxLossBps)` only.

2) SimpleHoldingAdapter (or SimpleAaveAdapter later)
   - Minimal adapter interface: `deposit/withdraw/totalAssets/emergencyUnwind`.
   - No swaps/callbacks; exact approvals; zero after use.

3) NGORegistrySimple (upgradeable)
   - `announceAdd(ngo)` → 48h → `add(ngo)`; immediate `revoke(ngo)`.

4) DonationPayer
   - `donate(asset, ngo, amount)` from authorized caller (vault); non‑reentrant; SafeERC20.

5) TreasurySimple
   - Receives protocol fees and allows owner sweep; minimal surface.

---

## 4) Core Behaviors

Harvest & split
- Permissionless `harvest(ngo)`: validates `ngo == currentNGO` and allowlist; computes harvested; sends fee to treasury; approves DonationPayer to send donation to NGO; resets baseline; opens a short harvest window (deposits paused only).

Safety & pausing
- `withdraw/redeem` always callable. Deposit/mint pausable by guardian and during harvest window.
- `emergencyUnwind(maxLossBps)` by guardian/owner: realize position back to underlying and reset baseline; withdrawals remain available; deposits paused only.

Parameters
- `donationPercentBps`: 5000/7500/10000 (per vault; set on init).
- `protocolFeeBps`: default 1% (≤ 1.5%).
- `tvlCap` per vault; `harvestWindowBlocks` (e.g., 20 blocks).

---

## 5) Invariants & Security

- Principal safety: withdrawals always succeed (venue liquidity permitting); never pausable.
- Harvest conservation: `harvested == fee + donated + retained` in all tests.
- No reentrancy: vault harvest and DonationPayer guarded; CEI.
- Token hygiene: reject fee‑on‑transfer/rebasing tokens via received==assets checks.
- Approvals: exact and zeroed; no infinite approvals.
- Guardian limits: only deposit pause and emergencyUnwind; negative tests enforce scope.

---

## 6) Interfaces (high‑level)

```solidity
interface ISimpleAdapter {
  function asset() external view returns (address);
  function vault() external view returns (address);
  function totalAssets() external view returns (uint256);
  function deposit(uint256 assets) external;
  function withdraw(uint256 assets, address to) external;
  function emergencyUnwind(uint16 maxLossBps) external returns (uint256);
}

interface INGORegistrySimple {
  function isAllowed(address ngo) external view returns (bool);
  function announceAdd(address ngo) external;
  function add(address ngo) external;
  function revoke(address ngo) external;
}

interface IDonationPayer {
  function donate(address asset, address ngo, uint256 amount) external;
}
```

Events: `Harvest`, `DonationPaid`, `DepositsPaused`, `CurrentNGOSet`, `CurrentNGOSwitched`, `EmergencyUnwind`, `ProtocolFeeSet`, `TVLCapSet`, `GuardianSet`.

---

## 7) Source Layout

```
/src
  /vault     SimpleVault4626Upgradeable.sol
  /adapter   SimpleHoldingAdapter.sol
  /ngo       NGORegistrySimple.sol  DonationPayer.sol
  /gov       TreasurySimple.sol
  /interfaces ISimpleAdapter.sol
```

---

## 8) Tests (Foundry)

Unit
- ERC‑4626 conformance across 6/18 decimals; cap enforcement on deposit/mint.
- Harvest identity: fee first, then donation; retained computed; events emitted.
- Withdraw‑always‑open under pause and harvest window.
- Approval hygiene: adapter and payer approvals are exact and zeroed.
- NGO delay: queue → 48h → switch; early harvest with wrong NGO reverts.

Invariants/Fuzz
- Principal conservation across random deposit/withdraw/harvest sequences.
- No reentrancy on `harvest()` and DonationPayer.
- Unwind bounds: realized loss ≤ `maxLossBps`; withdrawals remain open.

Integration
- Per vault: deposit → adapter accrues → harvest(ngo) → donation sent → withdraw.

---

## 9) Governance & Runbooks

- Owner (Gnosis Safe) and Guardian (EOA/Safe module).
- Owner: set `protocolFeeBps`, `tvlCap`, queue/switch `currentNGO`, set Guardian.
- Guardian: `pauseDeposits`, `emergencyUnwind`.

SOPs
- Harvest: confirm NGO allow‑listed → `harvest(currentNGO)` → monitor `Harvest` and `DonationPaid`.
- Emergency: pause deposits → `emergencyUnwind(maxLossBps)` → verify assets → unpause when safe.
- NGO lifecycle: `announceAdd` → 48h → `add`; `revoke` blocks future harvests.

Monitoring: index all events; alerts on parameter changes, pauses, unwinds, failed harvests, donation transfers.

---

## 10) Deployment Plan

Order: NGORegistrySimple (proxy) → TreasurySimple → DonationPayer → (x3) SimpleVault4626Upgradeable (proxy; splits 50/75/100) → wire Owner/Guardian → set tvlCaps/fees → queue currentNGO (48h) → open deposits.

---

## 11) Acceptance Criteria (DoD)

✅ Three vaults deployed with fixed splits (50/75/100).
✅ ERC‑4626 conformance; withdrawals cannot be paused.
✅ Single adapter; no swaps/callbacks; approval hygiene.
✅ Harvest identity holds; donations only to current allow‑listed NGO.
✅ Protocol fee ≤ 1.5%; TVL cap enforced.
✅ Guardian limited to deposit pause + emergencyUnwind; negative tests green.
✅ ≥ 85% coverage on core; invariants/fuzz green; gas report produced.
✅ Runbooks published; monitoring live.

---

## 12) References

- ERC‑4626 standard & OZ docs. (Ethereum Improvement Proposals, OpenZeppelin Docs)
- Aave V3 developer docs (aave.com)

