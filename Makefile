-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make fund ARGS=\"--network mainnet\""
	@echo ""
	@echo "Available Networks:"
	@echo "  - mainnet"
	@echo "  - sepolia"
	@echo "  - base-mainnet"
	@echo "  - base-sepolia"

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.1.0 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit && forge install foundry-rs/forge-std@v1.5.3 --no-commit && forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

coverage :; forge coverage --report debug > coverage-report.txt

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# Network Args
LOCAL_NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ETH_NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

BASE_NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv

# Conditions for ETH Networks
ifeq ($(findstring --network mainnet,$(ARGS)),--network mainnet)
	ETH_NETWORK_ARGS := --rpc-url $(MAINNET_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	ETH_NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# Conditions for Base Networks
ifeq ($(findstring --network base-mainnet,$(ARGS)),--network base-mainnet)
	BASE_NETWORK_ARGS := --rpc-url $(BASE_MAINNET_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network base-sepolia,$(ARGS)),--network base-sepolia)
	BASE_NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv
endif

# Deploy Commands
make deploy-eth:
	forge script script/DeploySVC.s.sol:DeploySVC $(ETH_NETWORK_ARGS)

make deploy-base:
	forge script script/DeploySVC.s.sol:DeploySVC $(BASE_NETWORK_ARGS)

make deploy-local:
	forge script script/DeploySVC.s.sol:DeploySVC $(LOCAL_NETWORK_ARGS)