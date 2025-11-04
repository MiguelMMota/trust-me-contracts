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

# Deploy to local network
deploy-local:
    forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to Sepolia testnet
deploy-sepolia:
    forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify

# Generate coverage report
coverage:
    forge coverage

# Snapshot gas usage
snapshot:
    forge snapshot

# Show contract sizes
size:
    forge build --sizes
