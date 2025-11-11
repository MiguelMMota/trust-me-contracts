# Load environment variables from .env file
set dotenv-load

# Default recipe (show available commands)
default:
    @just --list

# Run tests with gas report
test-gas:
    forge test --gas-report

# Run specific test file
test-file FILE:
    forge test --match-path {{FILE}} -vvv

# ===========================================
# Full System Deployments
# ===========================================

# Deploy all contracts to local network (Anvil)
deploy-local:
    forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
    @echo "\nUpdating dapp contract addresses..."
    @./script/update-dapp-addresses.sh anvil

# Deploy all contracts to Sepolia testnet
deploy-sepolia:
    forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account sepoliaKey --password-file .password --broadcast --verify
    @echo "\nDeployment complete! Checking proxy verification status..."
    @sleep 5
    @just verify-proxies sepolia
    @echo "\nUpdating dapp contract addresses..."
    @./script/update-dapp-addresses.sh sepolia

# ===========================================
# Contract Upgrades
# ===========================================

# Upgrade single contract on specified network (local or sepolia)
# E.g.: just upgrade Challenge sepolia upgrades the Challenge contract on the Sepolia testnet
upgrade CONTRACT NETWORK:
    #!/usr/bin/env bash
    if [ "{{NETWORK}}" = "local" ]; then
        forge script script/upgrade/Upgrade{{CONTRACT}}.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
    elif [ "{{NETWORK}}" = "sepolia" ]; then
        forge script script/upgrade/Upgrade{{CONTRACT}}.s.sol --rpc-url $SEPOLIA_RPC_URL --account sepoliaKey --password-file .password --broadcast --verify
    else
        echo "Error: Network must be 'local' or 'sepolia'"
        exit 1
    fi

# Show contract sizes
size:
    forge build --sizes

coverage:
    forge coverage --no-match-coverage script

# ===========================================
# Verification
# ===========================================

# Verify all proxy contracts on Etherscan
verify-proxies NETWORK:
    ./script/verify-proxies.sh {{NETWORK}}