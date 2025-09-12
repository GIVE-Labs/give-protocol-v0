 -include .env

.PHONY: all build clean fmt test test-gas install anvil \
        mock-asset mvp-deploy mvp-deploy-holding mvp-deploy-mock mvp-deploy-aave \
        mvp-queue-ngo mvp-switch-ngo ngo-announce ngo-add time-48h \
        approve deposit redeem harvest balances last-log test-fork-aave

# Defaults for local Anvil
RPC_URL           ?= http://127.0.0.1:8545
# Use the private key that corresponds to DEPLOYER by default (Anvil acct #0)
# DEPLOYER (acct #0): 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# PK for acct #0:     0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_PK          ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# PK is the private key used for broadcast. Defaults to ANVIL_PK for local, override for testnet/mainnet.
PK                ?= $(ANVIL_PK)
DEPLOYER          ?= 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Owner/guardian (used by deployment script)
OWNER             ?= $(DEPLOYER)
GUARDIAN          ?= $(DEPLOYER)

# Contract addresses (fill after deploy)
ASSET             ?=
REG               ?=
VAULT             ?= # set this when using queue/switch targets
NGO               ?=

USE_AAVE          ?= false
ATOKEN            ?=
AAVE_POOL         ?=
USE_MOCK_YIELD    ?= false
YIELD_RATE_WAD    ?= 1000000000 # ~3.15% APR; increase for faster local accrual

all: build

clean: ; forge clean
build: ; forge build
fmt:   ; forge fmt
test:  ; forge test -vv
test-gas: ; forge test --gas-report -vv

# Install external dependencies into lib/
install:
	forge install \
	  OpenZeppelin/openzeppelin-contracts \
	  OpenZeppelin/openzeppelin-contracts-upgradeable \
	  foundry-rs/forge-std

anvil: ; anvil --block-time 1

# ----------------------------
# Deploy helpers
# ----------------------------

# Deploy a mintable mock ERC20 (default 6 decimals, 1,000,000 units to broadcaster)
mock-asset:
	forge script script/DeployMockAsset.s.sol:DeployMockAsset \
	  --rpc-url $(RPC_URL) --private-key $(PK) --broadcast -vv

mvp-deploy:
	OWNER=$(OWNER) GUARDIAN=$(GUARDIAN) ASSET=$(ASSET) NGO_MANAGER=$(OWNER) \
	USE_AAVE=$(USE_AAVE) ATOKEN=$(ATOKEN) AAVE_POOL=$(AAVE_POOL) \
	USE_MOCK_YIELD=$(USE_MOCK_YIELD) YIELD_RATE_WAD=$(YIELD_RATE_WAD) \
	forge script script/DeployMVP.s.sol:DeployMVP --rpc-url $(RPC_URL) --private-key $(PK) --broadcast -vv

# Shortcut: holding adapter (no venue), good for local/mock USDC
mvp-deploy-holding:
	$(MAKE) mvp-deploy USE_AAVE=false USE_MOCK_YIELD=false

# Shortcut: mock yield adapter (simulated accrual); requires MockERC20 asset
mvp-deploy-mock:
	$(MAKE) mvp-deploy USE_MOCK_YIELD=true USE_AAVE=false YIELD_RATE_WAD=$(YIELD_RATE_WAD)

# Shortcut: Aave adapter; requires ASSET, ATOKEN, AAVE_POOL
mvp-deploy-aave:
	@if [ -z "$(ASSET)" ] || [ -z "$(ATOKEN)" ] || [ -z "$(AAVE_POOL)" ]; then \
	  echo "Set ASSET, ATOKEN, AAVE_POOL for Aave deployment"; exit 1; \
	fi
	$(MAKE) mvp-deploy USE_AAVE=true USE_MOCK_YIELD=false

# StrategyManager: schedule + activate adapter (use deployer as adapter for demo)
sm-schedule:
	cast send $(SM) "scheduleActiveAdapter(address)" $(DEPLOYER) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

time-6m:
	cast rpc anvil_increaseTime 15552000 --rpc-url $(RPC_URL) && \
	cast rpc evm_mine --rpc-url $(RPC_URL)

sm-activate:
	cast send $(SM) "setActiveAdapter(address)" $(DEPLOYER) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

# NGO add (two-step)
ngo-announce:
	cast send $(REG) "announceAdd(address)" $(NGO) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

time-48h:
	cast rpc anvil_increaseTime 172800 --rpc-url $(RPC_URL) && \
	cast rpc evm_mine --rpc-url $(RPC_URL)

ngo-add:
	cast send $(REG) "add(address)" $(NGO) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

mvp-queue-ngo:
	cast send $(VAULT) "queueCurrentNGO(address)" $(NGO) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

mvp-switch-ngo:
	cast send $(VAULT) "switchCurrentNGO()" \
	  --private-key $(PK) --rpc-url $(RPC_URL)

# ----------------------------
# User actions
# ----------------------------

# Approve vault to spend ASSET
AMT ?= 100000000 # 100 units for 6-dec tokens; adjust per decimals
approve:
	@if [ -z "$(VAULT)" ]; then echo "Set VAULT address"; exit 1; fi
	cast send $(ASSET) "approve(address,uint256)" $(VAULT) $(AMT) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

# Deposit assets into the vault
RECEIVER ?= $(OWNER)
deposit:
	@if [ -z "$(VAULT)" ]; then echo "Set VAULT address"; exit 1; fi
	cast send $(VAULT) "deposit(uint256,address)" $(AMT) $(RECEIVER) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

# Redeem all shares from the vault to RECEIVER
redeem:
	@if [ -z "$(VAULT)" ]; then echo "Set VAULT address"; exit 1; fi
	SHARES_HEX=$$(cast call $(VAULT) "balanceOf(address)" $(OWNER) --rpc-url $(RPC_URL)); \
	SHARES=$$(cast --to-dec $$SHARES_HEX); \
	cast send $(VAULT) "redeem(uint256,address,address)" $$SHARES $(RECEIVER) $(OWNER) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

# Harvest to current NGO (requires NGO queued+switched and allow-listed)
harvest:
	@if [ -z "$(VAULT)" ] || [ -z "$(NGO)" ]; then echo "Set VAULT and NGO"; exit 1; fi
	cast send $(VAULT) "harvest(address)" $(NGO) \
	  --private-key $(PK) --rpc-url $(RPC_URL)

# Quick balances view (Treasury, NGO must be set manually if desired)
balances:
	@if [ -z "$(VAULT)" ]; then echo "Set VAULT address"; exit 1; fi
	cast call $(ASSET) "balanceOf(address)(uint256)" $(VAULT) --rpc-url $(RPC_URL)

# Show the last broadcast JSON path for MVP
last-log:
	@echo "broadcast/DeployMVP.s.sol/$$(( $$(cast chain-id --rpc-url $(RPC_URL)) ))/run-latest.json"

test-fork-aave:
	FORK=1 ASSET=$(ASSET) ATOKEN=$(ATOKEN) AAVE_POOL=$(AAVE_POOL) \
	  forge test --match-contract Test11_AaveAdapter_Fork -vv
