 -include .env

.PHONY: all build clean fmt test test-gas anvil deploy-anvil demo-e2e \
        sm-schedule sm-activate time-6m time-1y ngo-add ngo-finalize \
        deposit harvest roll finalize-root settle approve-router \
        claim-ngo claim-user

# Defaults for local Anvil
RPC_URL           ?= http://127.0.0.1:8545
# Use the private key that corresponds to DEPLOYER by default (Anvil acct #0)
# DEPLOYER (acct #0): 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# PK for acct #0:     0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_PK          ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER          ?= 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Contract addresses (fill after deploy)
ASSET             ?=
SM                ?=
VAULT             ?=
REG               ?=
ROUTER            ?=

# Demo values
HARVEST           ?= 100000000000000000000  # 100e18
FEE               ?= 1000000000000000000    # 1e18 (1%)
DONATION          ?= 30000000000000000000   # 30e18
USER_YIELD        ?= 69000000000000000000   # 69e18
EPOCH             ?= 0
DONOR             ?= $(DEPLOYER)
AMOUNT            ?= $(USER_YIELD)

all: build

clean: ; forge clean
build: ; forge build
fmt:   ; forge fmt
test:  ; forge test -vv
test-gas: ; forge test --gas-report -vv

anvil: ; anvil --block-time 1

deploy-anvil:
	forge script script/DeployAnvil.s.sol:DeployAnvil \
	  --rpc-url $(RPC_URL) --broadcast -vv

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
ngo-add:
	cast send $(REG) "queueAdd(address)" $(DEPLOYER) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

time-1y:
	cast rpc anvil_increaseTime 31536000 --rpc-url $(RPC_URL) && \
	cast rpc evm_mine --rpc-url $(RPC_URL)

ngo-finalize:
	cast send $(REG) "finalizeAdd(address)" $(DEPLOYER) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

# User deposit flow
deposit:
	cast send $(ASSET) "mint(address,uint256)" $(DONOR) 1000000000000000000000 \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)
	cast send $(ASSET) "approve(address,uint256)" $(VAULT) 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)
	cast send $(VAULT) "deposit(uint256,address)" 100000000000000000000 $(DONOR) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

harvest:
	cast send $(VAULT) "reportHarvest(uint256)" $(HARVEST) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

roll:
	cast send $(VAULT) "rollEpoch()" \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

# Build a single-leaf Merkle root for (USER, AMOUNT) and finalize
finalize-root:
	ROOT=$$(cast keccak $$(cast abi-encode --packed "address,uint256" $(DONOR) $(AMOUNT))) && \
	cast send $(VAULT) \
	  "finalizeEpochRoot(uint256,bytes32,(uint256,uint256,uint256,uint256))" \
	  $(EPOCH) $$ROOT "($(HARVEST),$(FEE),$(DONATION),$(USER_YIELD))" \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

settle:
	cast send $(ROUTER) "settleEpoch(uint256)" $(EPOCH) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

approve-router:
	cast rpc anvil_impersonateAccount $(VAULT) --rpc-url $(RPC_URL)
	cast send $(ASSET) "approve(address,uint256)" $(ROUTER) 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
	  --from $(VAULT) --rpc-url $(RPC_URL)

claim-ngo:
	cast send $(ROUTER) "claim(address,address)" $(DEPLOYER) $(DEPLOYER) \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

claim-user:
	cast send $(VAULT) "claimUserYield(uint256,uint256,bytes32[])" $(EPOCH) $(AMOUNT) "[]" \
	  --private-key $(ANVIL_PK) --rpc-url $(RPC_URL)

# One-shot demo: deploy + activate + deposit + harvest + roll + finalize + add NGO + settle + approve + claim
demo-e2e: deploy-anvil sm-schedule time-6m sm-activate deposit harvest roll finalize-root ngo-add time-1y ngo-finalize settle approve-router claim-ngo claim-user
