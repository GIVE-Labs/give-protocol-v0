# GIVE Protocol — Change Log

All notable changes to this repository will be documented in this file. This project adheres to the build brief in AGENTS.md.

## [0.1.0] - Bootstrap (Scaffold + Specs)
- Initialized Foundry configuration (`foundry.toml`) with Solidity 0.8.24 and remappings for intended libraries.
- Created canonical source layout matching AGENTS.md:
  - `contracts/core`: `GiveProtocolCore.sol`, `ACLManager.sol`, `EmergencyController.sol`
  - `contracts/vault`: `BoringVault4626.sol`, `StrategyManager.sol`, `EpochTypes.sol`
  - `contracts/adapters`: `PendleAdapter.sol`, `EulerAdapter.sol`
  - `contracts/manager`: `ManagerWithMerkleVerification.sol`
  - `contracts/decoders`: `UniswapV3DecoderAndSanitizer.sol`, `PendleDecoderAndSanitizer.sol`, `EulerDecoderAndSanitizer.sol`, `ERC4626DecoderAndSanitizer.sol`, `GiveAggregatorDecoderAndSanitizer.sol`
  - `contracts/donation`: `DonationRouter.sol`, `NGORegistry.sol`
  - `contracts/governance`: `Treasury.sol`, `Timelock.sol`
  - `contracts/token`: `GIVEToken.sol`, `IncentivesController.sol`, `EmissionController.sol`
  - `contracts/staking`: `Staking.sol`
  - `contracts/proxy`: `Proxy.sol`
  - `contracts/interfaces`: `IBoringVault4626.sol`, `IStrategyManager.sol`, `IAdapter.sol`, `IDonationRouter.sol`, `IIncentivesController.sol`
- Added storage-only, abstract skeletons across all modules with:
  - Canonical events from AGENTS.md (observability) and custom errors.
  - Storage gaps for upgradeability.
  - No business logic implemented yet (Spec Agent deliverable).
- Added placeholder forge scripts in `script/` for deployment runs.

## Planned Next Milestones
// 0.2.0 achieved (see below)
- 0.3.0 — StrategyManager auth, single active adapter invariant, caps, rotation timelock (Vault/Strategy Agent).
- 0.4.0 — DonationRouter + NGORegistry flows (settle/claim, two-step add with timelocks) (Donation/NGO Agent).
- 0.5.0 — ManagerWithMerkleVerification + decoders/sanitizers for UniswapV3, Pendle, Euler, ERC-4626 (Manager/Decoder Agent).
- 0.6.0 — Security pass (invariants/fuzz, reentrancy, auth, timelocks); gas reports (Security Agent).
- 0.7.0 — Optional tokenomics: GIVE incentivized ERC-20 + incentives/staking skeleton wiring (Tokenomics Agent).
- 0.8.0 — Testnet deployment, runbooks, dashboards (DevOps Agent).

## [0.2.0] - Vault Implementation (ERC-4626 + Epochs/Merkle)
- Added `contracts/vault/GiveVault4626.sol` implementing:
  - Full ERC-4626 via OpenZeppelin with deposit/mint gated by a harvest window; withdraw/redeem always available.
  - `reportHarvest(uint256)` restricted to the active adapter via `IStrategyManager.activeAdapter()`.
  - Protocol fee taken immediately on harvest and transferred to `treasury`; emits `FeeCollected`.
  - Harvest window opened per report for `harvestWindowBlocks` blocks (deposits/mints paused only).
  - Epoch lifecycle via `rollEpoch()`; emits `EpochRolled`.
  - Merkle root finalization with conservation checks and immutability; emits `EpochRootFinalized`.
  - Merkle-based `claimUserYield` with per-user/epoch bitmap, bounded by `epochTotals.userYieldTotal`; emits `UserYieldClaimed`.
  - Donation share setter enforcing {5000, 7500, 10000} bps effective next epoch; emits `DonationShareSet`.
  - Views: `donationAsset()`, `donationAmountForEpoch()`, `epochRoot()`.
- Wired OZ imports and MerkleProof; build verified under Foundry.

## [0.3.0] - Strategy Manager (Auth + Timelock + Caps)
- Implemented `contracts/vault/StrategyManager.sol` using OpenZeppelin `AccessControl`:
  - Role: `STRATEGY_MANAGER_ROLE`; admin provided in constructor.
  - Enforces single active adapter invariant with timelocked rotation (6 months):
    - `scheduleActiveAdapter(address)` queues rotation; emits `AdapterRotationScheduled`.
    - `setActiveAdapter(address)` only executes the queued adapter after ETA; emits `ActiveAdapterSet`.
    - `cancelActiveAdapterRotation()` supports aborting a queued rotation; emits `AdapterRotationCancelled`.
  - Risk parameter setters: `setCaps(uint256,uint16)` with bounds, emits `CapsSet`.
- Verified build across repository with Foundry.

## [0.4.0] - Donation Router + NGO Registry
- Implemented `contracts/donation/NGORegistry.sol` using OpenZeppelin `AccessControl` with `NGO_MANAGER_ROLE`:
  - Two-step add: `queueAdd` (1y delay) and `finalizeAdd` (activates NGO; timestamps recorded).
  - Revoke paths: `revoke` (normal; expected 6m delay enforced externally) and `emergencyRevoke` (0 delay). Both set `revokedAt`.
  - Tracks `allowedCount` and membership timestamps; exposes `isEligibleAt(ngo, ts)` to query eligibility at a given time.
- Implemented `contracts/donation/DonationRouter.sol` with `ReentrancyGuard` and `AccessControl` (admin setter for registry):
  - `settleEpoch(epoch)` is permissionless and snapshots `donationAmount`, `allowedCount`, and a settle timestamp per epoch. Requires `epochRoot` finalized.
  - `claim(ngo, to)` sums pro-rata shares across settled epochs since the NGO's cursor, validating eligibility at the epoch's settle timestamp. Transfers underlying from the vault via `transferFrom` (requires allowance).
  - Exposes `donationAsset()` view passthrough to vault; emits `EpochSettled` and `NGOClaim`.
- Notes: Router is pull-based and does not custody funds; vault must approve Router to spend `donationAsset` up to donation totals.

## [0.4.1] - Emergency Revoke Semantics + MVP Test Hardening
- Fixed eligibility edge-case so emergency revoke blocks only future payouts:
  - `NGORegistry.isEligibleAt` now treats `ts <= revokedAt` as eligible, aligning with §2.3 “emergency revoke: blocks future payouts only”.
- Added tests to ensure a minimal MVP is verifiable end-to-end:
  - Emergency flows: `DonationRouter.t.sol::test_EmergencyRevokeBlocksFutureEpochs` (now passing) and `NGORegistry.t.sol::test_RevokeAndEmergencyRevoke`.
  - Vault donation share: `Vault.t.sol::test_DonationShare_OnlyAllowedAndNextEpoch` validates {50/75/100}% enforcement and next-epoch effectiveness via event.
  - Epoch conservation guard: `Vault.t.sol::test_FinalizeRoot_ConservationChecked` ensures root finalization reverts if `harvested != fee + donation + userYield`.
- Full suite status: 12 tests passed (unit + integration + emergency). Gas report captured for core paths.
- Outcome: 0.1.0–0.4.1 features constitute a minimum MVP per AGENTS.md — users can deposit, yield is harvested, epochs are rolled and finalized, NGOs are credited and can claim, with emergency revoke preventing future payouts without impacting settled ones.

## Dependency Installation (pending approval)
- `forge install` the following official libraries:
  - `OpenZeppelin/openzeppelin-contracts` and `OpenZeppelin/openzeppelin-contracts-upgradeable`
  - `foundry-rs/forge-std`
  - `Se7en-Seas/boring-vault` (references/decoders)
- After installation, ensure imports compile and add minimal unit tests.

## [0.4.2] - Tooling: Install Target
- Added `install` target in `Makefile` to fetch dependencies via `forge install`:
  - `OpenZeppelin/openzeppelin-contracts`, `OpenZeppelin/openzeppelin-contracts-upgradeable`, `foundry-rs/forge-std`, `Se7en-Seas/boring-vault`.
- Intention: run `make install` before build/test to ensure `lib/` is populated.

## [0.5.0] - Manager (Base Merkle Gating)
- Implemented a minimal concrete `ManagerWithMerkleVerification`:
  - Stores `allowListRoot`, `owner`, and immutable `boringVault` reference.
  - `setAllowListRoot` gated by `owner` and evented.
  - `forward(target,data,proof)` verifies Merkle inclusion for leaf `keccak256(abi.encode(target, selector, keccak256(data))))` then performs low-level call.
  - Emits `Forwarded` on success; reverts `NotAllowed` on invalid proof.
  - Note: decoders/sanitizers remain pending; this is a safe base to layer them on.
- Tests added (`test/unit/Test05_ManagerWithMerkle.t.sol`):
  - Root can only be set by owner.
  - Forwarding succeeds for authorized leaf, reverts for wrong target/mutated data.
  - Single-leaf Merkle proof path validates gating behavior.
