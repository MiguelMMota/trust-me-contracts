# Default recipe (show available commands)
default:
    @just --list

# Build smart contracts
build:
    forge build

# Run tests
test:
    forge test

# Run tests with gas report
test-gas:
    forge test --gas-report

# Run tests with verbosity
test-v:
    forge test -vvv

# Run specific test file
test-file FILE:
    forge test --match-path {{FILE}} -vvv

# Clean build artifacts
clean:
    forge clean

# Format Solidity files
fmt:
    forge fmt

# Check formatting without modifying files
fmt-check:
    forge fmt --check

# Lint contracts using the custom /lint command
lint FILE:
    @echo "Linting {{FILE}}..."

# Install dependencies
install:
    forge install

# Update dependencies
update:
    forge update

# Run local Anvil node
anvil:
    anvil

# ===========================================
# Full System Deployments
# ===========================================

# Deploy all contracts to local network (Anvil)
deploy-local:
    forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy all contracts to Sepolia testnet
deploy-sepolia:
    forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account sepoliaKey --password-file .password --broadcast --verify

# ===========================================
# Individual Contract Deployments
# ===========================================

# Deploy single contract to specified network (local or sepolia)
deploy-contract CONTRACT NETWORK:
    #!/usr/bin/env bash
    if [ "{{NETWORK}}" = "local" ]; then
        forge script script/deploy/Deploy{{CONTRACT}}.s.sol --rpc-url http://localhost:8545 --broadcast
    elif [ "{{NETWORK}}" = "sepolia" ]; then
        forge script script/deploy/Deploy{{CONTRACT}}.s.sol --rpc-url $SEPOLIA_RPC_URL --account sepoliaKey --password-file .password --broadcast --verify
    else
        echo "Error: Network must be 'local' or 'sepolia'"
        exit 1
    fi

# Deploy TopicRegistry to local network
deploy-topic-registry-local:
    forge script script/deploy/DeployTopicRegistry.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy User to local network
deploy-user-local:
    forge script script/deploy/DeployUser.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy Challenge to local network
deploy-challenge-local:
    forge script script/deploy/DeployChallenge.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy PeerRating to local network
deploy-peer-rating-local:
    forge script script/deploy/DeployPeerRating.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy ReputationEngine to local network
deploy-reputation-engine-local:
    forge script script/deploy/DeployReputationEngine.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy Poll to local network
deploy-poll-local:
    forge script script/deploy/DeployPoll.s.sol --rpc-url http://localhost:8545 --broadcast

# ===========================================
# Contract Upgrades
# ===========================================

# Upgrade single contract on specified network (local or sepolia)
upgrade-contract CONTRACT NETWORK:
    #!/usr/bin/env bash
    if [ "{{NETWORK}}" = "local" ]; then
        forge script script/upgrade/Upgrade{{CONTRACT}}.s.sol --rpc-url http://localhost:8545 --broadcast
    elif [ "{{NETWORK}}" = "sepolia" ]; then
        forge script script/upgrade/Upgrade{{CONTRACT}}.s.sol --rpc-url $SEPOLIA_RPC_URL --account sepoliaKey --password-file .password --broadcast --verify
    else
        echo "Error: Network must be 'local' or 'sepolia'"
        exit 1
    fi

# Upgrade TopicRegistry on local network
upgrade-topic-registry-local:
    forge script script/upgrade/UpgradeTopicRegistry.s.sol --rpc-url http://localhost:8545 --broadcast

# Upgrade User on local network
upgrade-user-local:
    forge script script/upgrade/UpgradeUser.s.sol --rpc-url http://localhost:8545 --broadcast

# Upgrade Challenge on local network
upgrade-challenge-local:
    forge script script/upgrade/UpgradeChallenge.s.sol --rpc-url http://localhost:8545 --broadcast

# Upgrade PeerRating on local network
upgrade-peer-rating-local:
    forge script script/upgrade/UpgradePeerRating.s.sol --rpc-url http://localhost:8545 --broadcast

# Upgrade ReputationEngine on local network
upgrade-reputation-engine-local:
    forge script script/upgrade/UpgradeReputationEngine.s.sol --rpc-url http://localhost:8545 --broadcast

# Upgrade Poll on local network
upgrade-poll-local:
    forge script script/upgrade/UpgradePoll.s.sol --rpc-url http://localhost:8545 --broadcast

# Generate coverage report
coverage:
    forge coverage

# Snapshot gas usage
snapshot:
    forge snapshot

# Show contract sizes
size:
    forge build --sizes
