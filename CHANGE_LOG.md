# GIVE Protocol — MVP Branch Change Log

All notable changes for the MVP (three‑vaults) branch are documented here.

## [0.1.0] — MVP Scaffold
- Added new MVP contract set:
  - `src/vault/SimpleVault4626Upgradeable.sol` — upgradeable ERC‑4626 vault with fixed donation split, withdraw‑always‑open, harvest without epochs, guardian deposit‑pause + emergencyUnwind, TVL cap, NGO 48h delay, UUPS.
  - `src/adapter/SimpleHoldingAdapter.sol` — minimal non‑upgradeable adapter that holds underlying and exposes totalAssets/deposit/withdraw/emergencyUnwind.
  - `src/ngo/NGORegistrySimple.sol` — upgradeable allowlist with 48h announce→add and immediate revoke.
  - `src/ngo/DonationPayer.sol` — non‑upgradeable payer; authorized callers pull transfer donations to NGOs.
  - `src/governance/TreasurySimple.sol` — minimal treasury for protocol fees (owner sweep).
  - `src/interfaces/ISimpleAdapter.sol` — adapter interface for MVP.
- Updated AGENTS.md with the MVP three‑vault build brief and locked decisions.
- Removed legacy epoch/Merkle pathway and related modules from compilation scope:
  - Deleted GiveVault4626, BoringVault4626, EpochTypes, DonationRouter, NGORegistry (legacy), ManagerWithMerkleVerification, all Decoders, their interfaces, legacy manager, and tests/scripts that depended on them.

## [0.2.0] — Comprehensive Tests + Wiring
- Added unit test suite covering core MVP behaviors:
  - Test01_SimpleVault_Core: deposits/withdrawals, TVL cap, harvest identity, harvest window behavior.
  - Test02_Approvals_Unwind_NGO: approval hygiene, emergencyUnwind behavior, NGO enforcement.
  - Test03_NGORegistrySimple: announce/add delay and revoke semantics.
  - Test04_DonationPayer: authorization and input validation.
  - Test05_Guardian_Scope: guardian abilities and owner‑only guards.
  - Test06_UUPS_Upgrade: owner‑only upgrade, post‑upgrade smoke check.
  - Test07_TVL_Cap_MintPreview: cap enforcement across mint path.
  - Test08_Harvest_EdgeCases: zero/near‑zero harvests and rounding checks.
  - Test09_TreasurySimple: receiveFee and sweep.
- Adapter: added `setVault(address)` for post‑proxy wiring; retains onlyVault gating for calls.
- Foundry: enabled `via_ir = true` to avoid stack‑too‑deep in upgradeable initializer.
- README.md: added usage, runbook, deployment guidance.

## [0.3.0] — Deploy Scripts + E2E
- Added `script/DeployMVP.s.sol` for deploying Treasury, NGORegistrySimple, DonationPayer, adapter, and three UUPS vaults (50/75/100) with env‑configurable params. Includes adapter wiring and payer authorization.
- Makefile targets for NGO announce/add, queue/switch NGO, and deployment hook.
- Integration test `Test10_E2E_MVP.t.sol` for deposit → harvest → donation → withdraw.

## [0.4.0] — Aave Adapter + Fork + Invariants
- Implemented `src/adapter/SimpleAaveAdapter.sol` using Aave V3 Pool supply/withdraw; exact approvals; emergencyUnwind.
- Fork test scaffold `test/fork/Test11_AaveAdapter_Fork.t.sol` (skips unless FORK env is set).
- Invariants/fuzz starter `test/invariants/Test12_Invariants.t.sol` (withdraw‑always‑open; approvals zero after ops).

## Planned Next Milestones
- 0.2.0 — Unit tests (ERC‑4626 math across 6/18 decimals, harvest identity, withdraw‑always‑open, TVL cap, approval hygiene, NGO delay), invariants/fuzz, gas report.
- 0.3.0 — Deploy scripts for Base Sepolia; three vault deployments (GIVE‑50/75/100), Guardian wiring, queue/switch currentNGO; Make targets.
- 0.4.0 — SimpleAaveAdapter (Aave V3.1 Base) and optional fork tests; emergencyUnwind drills; postUpgrade smoke checks.
