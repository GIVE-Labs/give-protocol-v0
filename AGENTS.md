# AGENTS.md — Build Plan for **GIVE Protocol** (Production)

**Owner:** Project Manager
**Audience:** AI coding agents (Codex/Copilot-class), Solidity engineers, QA, DevOps, Security
**Status:** Authoritative build brief (production-ready)
**Architecture:** “Give Protocol.png” (smart-contract layer, vault-centric accounting, Strategy Manager)
**Grounding references:** ERC-4626 tokenized vaults, BoringVault + ManagerWithMerkleVerification (Decoders & Sanitizers), Aave V3 incentivized ERC20 pattern. ([Ethereum Improvement Proposals][1], [OpenZeppelin Docs][2], [GitHub][3], [Veda][4], [aave.com][5])

---

## 1) Mission & Scope

**Mission.** Ship a **no-loss donation protocol** where users deposit into a **single BoringVault (ERC-4626)**; **only harvested yield** is routed to **approved NGOs**. Accounting is **Merkle-based per epoch**. Users pick a **donation share** of **50% / 75% / 100%**; the remainder is user-claimable. Governance is **multisig + long timelocks (6m / 1y / 2y)**. Optional extensions: staking of vault shares and a **GIVE** token that follows an **incentivized ERC-20** model (hooks to a rewards controller, inspired by Aave V3). ([Ethereum Improvement Proposals][1], [aave.com][5])

**Out-of-scope (v1):** leverage/borrowing, multiple vault flavors, DAO voting, cross-chain.

---

## 2) System Requirements (canonical)

> This section is **the** implementation contract for agents. If any other doc conflicts, this wins.

### 2.1 Contracts (one box = one contract)

* **Proxy (UUPS or Transparent)**
  Upgrade gate via **Upgrader** role behind **Timelock**.

* **GiveProtocolCore**
  Orchestrator. Holds module addresses & global params. Stores (or reads) user **donation share** (50/75/100). Emits config events.

* **ACLManager**
  Roles: `Admin`, `Upgrader`, `NGOManager`, `StrategyManager`, `OracleManager`, `Treasury`, `Pauser`, `Keeper(opt)`.

* **EmergencyController**
  Per-selector pause/unpause. **Must never** pause `withdraw()`/`redeem()`.

* **StrategyManager** *(replaces “Vault Manager”)*
  One **active adapter** (allow-listed) at a time for the vault; TVL and exposure caps; adapter rotation is timelocked.

* **BoringVault (ERC-4626 + Merkle Accounting)**
  Single instance. SafeERC20 deposits/withdraws; **harvest window** (deposits/mint paused briefly around harvest; withdrawals remain open).

  * `reportHarvest(amount)` — **only** active adapter.
  * `rollEpoch()` — permissionless or Keeper-gated; closes E, opens E+1; snapshots counters.
  * **Protocol fee** is taken **before** split; fee to `Treasury`.
  * **Donation share**: per user ∈ {5000, 7500, 10000 bps}; effective **next epoch**.
  * **Merkle accounting**: at/after `rollEpoch()`, publish `epochRoot` and `epochTotals` (harvested, fee, donation, userYield).
  * `claimUserYield(epoch, amount, proof)` → verifies leaf under `epochRoot[epoch]`; one-shot per user/epoch.
  * Expose `donationAmountForEpoch(epoch)` & `donationAsset()` for Router.

* **Strategy Adapters** (e.g., `PendleAdapter`, `EulerAdapter`)
  Stateless; **no principal custody**; realize yield to vault asset then call `reportHarvest`. Params set by StrategyManager.

* **DonationRouter**
  Pull-based NGO claims. Reads vault donation totals per epoch, credits NGO balances, `claim(ngo)` to withdraw. Uses `NGORegistry`.

* **NGORegistry & Verifier**
  Minimal allowlist; two-step add (timelocked), normal revoke (6m) or emergency revoke (0 delay; only blocks **future** payouts).

* **Treasury**
  Receives protocol fees (≤ **MAX\_FEE\_BPS**), funds ops & **POL** (protocol-owned liquidity).

* **GIVE Token (Incentivized ERC-20)** *(optional milestone)*
  ERC-20 with **incentive hooks** → calls `IncentivesController.handleAction(...)` on transfer/mint/burn. Emissions via `EmissionController`. Pattern follows **Aave’s incentivized tokenization** approach. ([aave.com][5])

* **EmissionController / IncentivesController / Staking** *(optional)*
  Staking of vault shares emits GIVE. IncentivesController accrues rewards on balance changes (Aave-style). ([aave.com][5])

### 2.2 Merkle-Verified **ManagerWithMerkleVerification** (for strategy calls)

All external protocol interactions executed by the vault’s manager use **DecoderAndSanitizer** modules to decode `msg.data`, extract addresses, and optionally **sanitize** inputs; the resulting bytes are checked against an **allow-list Merkle root** before forwarding the call. Build decoders for **Uniswap V3**, **Pendle**, **Euler**, and **ERC-4626** targets you will touch; override colliding selectors in an aggregate decoder. ([Veda][4])

**Why:** constrains strategist power to a precise allow-list (router, pools, markets, recipients), reducing blast radius. Audit notes & remediation patterns exist in public reviews. ([0xmacro.com][6])

### 2.3 Governance & Timelocks

* **Upgrades:** **1 year**
* **Risk params (caps, active strategy):** **6 months**
* **MAX\_FEE\_BPS changes:** **1 year**
* **Strategy template changes:** **1 year**
* **NGO add:** **1 year**
* **NGO revoke (normal):** **6 months**
* **NGO revoke (emergency):** **0 delay** (blocks future payouts only; dual-multisig)

### 2.4 Protocol Parameters

* **Donation share options:** {50%, 75%, 100%} (bps set {5000, 7500, 10000}).
* **Protocol fee:** default 1%, ceiling **MAX\_FEE\_BPS** = 1.5% (immutable or timelocked).
* **Epoch length:** 1 day.
* **Harvest window:** 10 blocks (deposits/mints paused only).
* **Caps:** per-vault TVL + per-user.
* **Single active adapter** invariant.
* **Staking/LM** rates bounded (if enabled).
* **ERC-4626** conformance required. ([Ethereum Improvement Proposals][1], [OpenZeppelin Docs][2])

### 2.5 Invariants & Safety

* **Principal safety:** users can always withdraw principal (≤ rounding).
* **Epoch conservation:** `harvested == fee + donationTotal + userYieldTotal`.
* **Merkle finality:** once `epochRoot` set, immutable; per-user single claim/epoch; sums bounded vs `epochTotals`.
* **Adapter auth:** only **active adapter** can `reportHarvest()`.
* **Pausing:** cannot pause `withdraw()`/`redeem()`; harvest window only blocks deposit/mint.
* **Timelocks:** enforce 6m/1y/2y queues for sensitive actions.

---

## 3) Deliverables for Agents

### 3.1 Source Layout

```
/src
  /core         GiveProtocolCore.sol  ACLManager.sol  EmergencyController.sol
  /vault        BoringVault4626.sol   StrategyManager.sol  EpochTypes.sol  GiveVault4626.sol
  /adapters     PendleAdapter.sol     EulerAdapter.sol     interfaces/
  /manager      ManagerWithMerkleVerification.sol
  /decoders     UniswapV3DecoderAndSanitizer.sol  PendleDecoderAndSanitizer.sol
                EulerDecoderAndSanitizer.sol  ERC4626DecoderAndSanitizer.sol
                GiveAggregatorDecoderAndSanitizer.sol
  /donation     DonationRouter.sol    NGORegistry.sol
  /governance   Treasury.sol          Timelock.sol
  /token        GIVEToken.sol         EmissionController.sol IncentivesController.sol
  /staking      Staking.sol
  /proxy        Proxy.sol (or OZ wrappers)
  /interfaces   I*.sol
/test
  /unit         /integration          /invariants
  // Naming convention: TestNN_Description.t.sol (e.g., Test01_VaultCore.t.sol, Test10_E2E.t.sol)
/script         deployment, role wiring, root tooling
```

### 3.2 Interfaces (high-level)

```solidity
interface IStrategyManager {
  function setActiveAdapter(address adapter) external;
  function setCaps(uint256 tvlCap, uint16 maxExposureBps) external;
  function activeAdapter() external view returns (address);
}

interface IAdapter {
  function reportHarvest(uint256 amount) external; // only active adapter
}

interface IBoringVault4626 /* ERC-4626 superset */ {
  function rollEpoch() external;
  function reportHarvest(uint256 harvested) external;
  function finalizeEpochRoot(uint256 epoch, bytes32 root, EpochTotals calldata totals) external;

  function setDonationShareBps(uint16 bps) external; // {5000, 7500, 10000}
  function claimUserYield(uint256 epoch, uint256 amount, bytes32[] calldata proof) external;

  function donationAsset() external view returns (address);
  function donationAmountForEpoch(uint256 epoch) external view returns (uint256);
  function epochRoot(uint256 epoch) external view returns (bytes32);
}

interface IDonationRouter {
  function settleEpoch(uint256 epoch) external;
  function claim(address ngo, address to) external returns (uint256);
}

interface IIncentivesController {
  function handleAction(address user, uint256 userBalance, uint256 totalSupply) external;
}
```

### 3.3 Events (observability)

`HarvestReported`, `EpochRolled`, `EpochRootFinalized`, `DonationShareSet`, `UserYieldClaimed`, `DonationCredited`, `NGOClaim`, governance changes (roles, caps, fee, adapter rotation), `FeeCollected`, `POLAdded`.

---

## 4) Build Plan (multi-agent)

### 4.1 Roles & Responsibilities

* **Spec Agent** — keeps System Requirements canonical; resolves ambiguities.
* **Core Solidity Agent** — `GiveProtocolCore`, `ACLManager`, `EmergencyController`, `Timelock`, `Treasury`.
* **Vault Agent** — `BoringVault4626` (ERC-4626 + epoch + Merkle), `StrategyManager`.
* **Adapters Agent** — `PendleAdapter`, `EulerAdapter`.
* **Manager/Decoder Agent** — ManagerWithMerkleVerification + all **DecodersAndSanitizers** with tests.
* **Donation/NGO Agent** — `DonationRouter`, `NGORegistry`.
* **Tokenomics Agent** *(optional)* — `GIVEToken` (incentivized ERC-20), `EmissionController`, `IncentivesController`, `Staking`. ([aave.com][5])
* **Security Agent** — invariants, fuzzing, Slither/Mythril, audit prep.
* **DevOps Agent** — deployments, scripts, envs, CI/CD, monitoring.

### 4.2 Workstream Order (gated)

1. **Scaffold & Governance**: Proxy, Core, ACL, Emergency, Timelock, Treasury.
2. **Vault & Strategy**: ERC-4626 vault with accounting; StrategyManager; single Adapter (Pendle **or** Euler) + harvest window.
3. **Merkle Accounting**: epoch counters, root finalize, user claim path with bitmap.
4. **Router/NGO**: settle epoch → credit NGOs; NGO claim; registry & two-step add.
5. **Manager + Decoders**: ManagerWithMerkleVerification; build UniswapV3/Pendle/Euler/4626 decoders; aggregate decoder; allow-list tooling. ([Veda][4])
6. **Security pass**: invariants/fuzz, reentrancy, auth, timelocks; gas reports.
7. *(Optional)* **Tokenomics**: GIVE (incentivized ERC-20) + staking + incentives controllers; LM skeleton. ([aave.com][5])
8. **Testnet**: deploy, runbooks, dashboards.

---

## 5) Coding Standards & Constraints

* **Solidity 0.8.x**, OZ libraries.
* **ERC-4626** compliance; read latest OZ docs for edge cases (rounding, non-18 decimals). ([OpenZeppelin Docs][2])
* **Checks-Effects-Interactions**, `ReentrancyGuard` where needed.
* **Custom errors**, `unchecked` only with proof of safety.
* **Events** for every sensitive state change.
* **No storage collisions** on upgrades; keep storage gaps.
* **Gas-aware**: caching, `immutable`/`constant`, tight structs.
* **Deterministic builds**, minimal external dependencies.
* **NatSpec required**: Public/external functions and constructors MUST have `@notice`/`@dev` and `@param`/`@return` tags; add concise contract headers.
* **Test naming**: Use `TestNN_Description.t.sol` with clear, behavior-oriented test function names.

---

## 6) Decoders & Sanitizers — Implementation Checklist

For each target protocol:

* **Uniswap V3**
  Implement selectors: `exactInput`, `mint`, `increaseLiquidity`, `decreaseLiquidity`, `collect`.

  * Parse 23-byte chunks in `params.path` (20 address + 3 fee); append `recipient`.
  * Sanitize: NFPM `ownerOf(tokenId) == boringVault`; forbid weird callbacks; deadline checks. ([Veda][7])

* **Pendle**
  Implement the specific functions the adapter will call (swaps PT/YT, add/remove liq, redeem after maturity).

  * Extract **all** addresses from struct/bytes; verify **router** and **market IDs** are allow-listed; maturity guards.

* **Euler**
  Implement deposit/withdraw/mint/burn for allowed markets; forbid callbacks; asset allow-list.

* **ERC-4626**
  Implement `deposit(uint256,address)`, `withdraw(uint256,address,address)`; override duplicates in an **Aggregator Decoder** to one body. ([Veda][7])

* **Aggregate collisions**
  Create `GiveAggregatorDecoderAndSanitizer.sol` inheriting all decoders; **override** identical selectors with a shared body.

* **Manager wiring**
  For each allowed action create Merkle leaf(s) capturing `(target, selector, sanitizedAddresses, bounds)` and publish root(s) per strategist or role. ([Veda][4])

---

## 7) Testing Strategy (Foundry)

### 7.1 Unit

* **Vault**: deposit/withdraw across 6/8/18-decimals; harvest window guards; fee cut; ERC-4626 conversions. ([OpenZeppelin Docs][2])
* **Epoch**: `reportHarvest` (only active adapter), `rollEpoch`, `finalizeEpochRoot` bounds vs counters.
* **Merkle**: wrong proof/epoch/root reverts; single claim bit; sum of leaves vs `epochTotals`.
* **Donation share**: transition effective **next epoch** only; {50,75,100}% enforced.
* **Router/NGO**: settle & claim; allowlist; gas-bounded loops.
* **Manager/Decoders**: selector parity tests, path parsing, ownership checks; Merkle verification gating real calls. ([Veda][7])
* **GIVE (opt.)**: IncentivizedERC20 hooks call `IncentivesController`; accrual math. ([aave.com][5])

### 7.2 Invariants / Fuzz

* Principal conservation; epoch conservation; single active adapter; cannot pause withdraw; timelock delays respected; no reentrancy on Router/claim.
* Fuzz donation share changes; NGOs per donor cap; large donor/NGO sets.

### 7.3 Integration

* E2E: deposit → harvest → roll → finalize root → user Merkle claim → NGO settle/claim.
* Adapter rotation mid-run; oracle staleness; slippage bounds; emergency NGO revoke (future payouts blocked only).

---

## 8) Security Requirements

**Must-hold invariants** (assert and test):

* `Σ userYield + Σ donation + fee == harvested`.
* Withdrawals cannot be paused.
* Only **active adapter** may `reportHarvest`.
* Merkle root immutable; one claim per user/epoch.
* Timelocks applied to Upgrades, Risk, MAX\_FEE\_BPS, Strategy template, NGO add/remove.

**Threat-model mitigations:**

* **Upgrade hijack/storage collision** → OZ proxies, gaps, timelocks, `postUpgrade()` smoke checks.
* **Share-price capture** → epoch snapshots & harvest windows.
* **Reentrancy (NGO claim)** → pull-based Router + CEI + guard.
* **Oracle manipulation/slippage** → freshness checks & tight slippage; fail-closed.
* **Decoder bypass** → Manager always verifies Sanitizer bytes vs Merkle root; unit tests for each selector. ([Veda][4])

---

## 9) DevOps & Runbooks

* **Environments**: anvil/local → testnet (Base/Arbitrum Sepolia) → mainnet(s).
* **Deployment order**: ACL → Emergency → NGORegistry → StrategyManager → Vault → Adapters → Router → Treasury → *(opt.)* Token+Incentives+Emission+Staking → Core(impl) → Proxy → role wiring (multisig + timelocks) → set active adapter → open deposits → schedule first epoch.
* **Epoch ops**: permissionless `rollEpoch()`; if using off-chain calculator, publish `epochRoot` + `epochTotals` then Router `settleEpoch`.
* **Emergency**: Pauser pauses selected selectors; withdrawals stay live.
* **Monitoring**: index events; alerts on role/param/adapter/timelock queue; harvest anomalies.

---

## 10) Acceptance Criteria (Definition of Done)

* ✅ ERC-4626 compliant vault; withdrawals never pauseable. ([Ethereum Improvement Proposals][1], [OpenZeppelin Docs][2])
* ✅ StrategyManager enforces **single active adapter** + caps.
* ✅ Epoch conservation identity holds for every epoch; property tests pass.
* ✅ Donation shares strictly {50/75/100}; next-epoch effect.
* ✅ Merkle roots immutable; one claim per user/epoch; sums match `epochTotals`.
* ✅ ManagerWithMerkleVerification gates all strategy calls via decoders & allow-list roots. ([Veda][4])
* ✅ Timelocks (6m/1y/2y) enforced for sensitive ops.
* ✅ Protocol fee ≤ **MAX\_FEE\_BPS**.
* ✅ (Opt.) Incentivized ERC-20 hooks & accrual verified. ([aave.com][5])
* ✅ Coverage ≥ 90% core paths; invariants/fuzz green; gas reports.

---

## 11) Prompts & Checklists for Agents

### 11.1 Spec Agent (prompt)

> “Generate Solidity interfaces and storage layouts for the contracts in §2.1. Ensure storage gap patterns for upgradeability. Emit events for every config change. Produce a mapping table of roles → functions. Do not implement business logic.”

### 11.2 Vault Agent (checklist)

* [ ] ERC-4626 math (preview, convert, rounding) vs OZ guidance. ([OpenZeppelin Docs][2])
* [ ] `reportHarvest` auth; harvest window; epoch snapshots.
* [ ] `finalizeEpochRoot` guards & conservation.
* [ ] `claimUserYield` Merkle verification + bitmap.

### 11.3 Manager/Decoder Agent (checklist)

* [ ] Build UniswapV3/Pendle/Euler/4626 decoders; parse all embedded addresses.
* [ ] Sanitize ownership (e.g., Uniswap V3 NFPM), routers, markets, callbacks, deadlines.
* [ ] Aggregate decoder overrides for duplicate selectors.
* [ ] Manager proof verification & failing tests for non-allow-listed addresses. ([Veda][7])

### 11.4 Tokenomics Agent (optional)

* [ ] GIVE ERC-20 with incentivized hooks; minimal `IncentivesController` accrual path. ([aave.com][5])
* [ ] Staking vault shares; emission schedule bounds; 100% donors boost (configurable).

### 11.5 Security Agent

* [ ] Invariants: principal/epoch/adapter/withdraw-pause.
* [ ] Reentrancy & CEI checks (Router, claim, adapters).
* [ ] Timelock queues & emergency revoke logic.
* [ ] Slither/Mythril; gas hotspots; audit-style report.

---

## 12) External References (primary)

* **ERC-4626 standard & guides** — EIP and OZ docs. ([Ethereum Improvement Proposals][1], [OpenZeppelin Docs][2], [ethereum.org][8])
* **BoringVault / ManagerWithMerkleVerification / Decoders & Sanitizers** — repos & docs (tutorial, architecture, audits). ([GitHub][3], [Veda][4])
* **Aave V3 developer docs (incentivized tokenization patterns)** — tokenization & incentives docs / repo. ([aave.com][5], [GitHub][9])

---

### Final note

This **AGENTS.md** is purposely exhaustive so autonomous agents can execute without clarifications. Use the cited primitives (ERC-4626, BoringVault Manager + Decoders, Aave-style incentives) as the canonical baseline.

[1]: https://eips.ethereum.org/EIPS/eip-4626?utm_source=chatgpt.com "ERC-4626: Tokenized Vaults"
[2]: https://docs.openzeppelin.com/contracts/5.x/erc4626?utm_source=chatgpt.com "ERC-4626"
[3]: https://github.com/Se7en-Seas/boring-vault?utm_source=chatgpt.com "Se7en-Seas/boring-vault"
[4]: https://docs.veda.tech/architecture-and-flow-of-funds/manager/managerwithmerkleverification?utm_source=chatgpt.com "ManagerWithMerkleVerification"
[5]: https://aave.com/docs/developers/smart-contracts?utm_source=chatgpt.com "Smart Contracts | Aave Protocol Documentation"
[6]: https://0xmacro.com/library/audits/sevenSeas-4?utm_source=chatgpt.com "Seven Seas A-4 | Macro Audits | The 0xMacro Library"
[7]: https://docs.veda.tech/integrations/boringvault-protocol-integration?utm_source=chatgpt.com "BoringVault Protocol Integration"
[8]: https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/?utm_source=chatgpt.com "ERC-4626 Tokenized Vault Standard"
[9]: https://github.com/aave/aave-v3-core "GitHub - aave/aave-v3-core: This repository contains the core smart contracts of the Aave V3 protocol."
