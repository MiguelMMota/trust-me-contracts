# Automated Deployment Pipeline

This repository uses GitHub Actions to automatically detect and upgrade contracts when changes are pushed to the `main` branch.

## How It Works

### 1. Change Detection
When you push to `main`, the workflow:
- Compares the current commit with the previous commit
- Identifies which `.sol` files in `src/` have changed
- Maps changed files to their respective upgrade scripts

### 2. Automated Upgrade Process
For each changed contract:
- Runs `forge build` and `forge test` to ensure everything compiles and passes
- Executes the corresponding upgrade script (e.g., `script/upgrade/UpgradeUser.s.sol`)
- The upgrade script:
  - Deploys a new implementation contract
  - Calls `upgradeToAndCall()` on the existing proxy (address never changes)
  - The proxy now points to the new implementation
- Verifies the new implementation on Etherscan
- Updates the deployment config in `deployments/`

### 3. Proxy Pattern
All contracts use the **UUPS (Universal Upgradeable Proxy Standard)** pattern:
- **Proxy Address**: Stable, never changes (users always interact with this)
- **Implementation Address**: Changes with each upgrade (contains the logic)

The deployment config (`deployments/sepolia.json`) stores only the **proxy addresses** because:
- These are the stable addresses users need
- Implementation addresses can be queried from the proxy if needed
- Change detection is based on source file diffs, not address comparison

## Setup Requirements

### GitHub Secrets
Configure these secrets in your repository settings:

```
DEPLOYER_PRIVATE_KEY - Private key of the deployment wallet
SEPOLIA_RPC_URL - RPC endpoint for Sepolia testnet
ETHERSCAN_API_KEY - API key for contract verification
```

### Deployment Config
Ensure your `deployments/sepolia.json` exists with proxy addresses:

```json
{
  "network": "sepolia",
  "chainId": 11155111,
  "timestamp": 1234567890,
  "topicRegistry": "0x...",
  "user": "0x...",
  "challenge": "0x...",
  "peerRating": "0x...",
  "reputationEngine": "0x...",
  "poll": "0x..."
}
```

## Workflow Triggers

The deployment workflow triggers on:
- Push to `main` branch
- Only when files in `src/*.sol` are modified

## Manual Deployment

To manually deploy/upgrade a specific contract:

```bash
# Upgrade User contract
forge script script/upgrade/UpgradeUser.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify

# Upgrade multiple contracts
forge script script/upgrade/UpgradeChallenge.s.sol --rpc-url sepolia --broadcast --verify
forge script script/upgrade/UpgradePoll.s.sol --rpc-url sepolia --broadcast --verify
```

## Deployment Scripts Structure

```
script/
├── Deploy.s.sol                    # Full initial deployment
├── config/
│   └── DeploymentConfig.sol        # Manages deployment addresses
├── deploy/                         # Initial deployment scripts
│   ├── DeployUser.s.sol
│   ├── DeployChallenge.s.sol
│   └── ...
└── upgrade/                        # Upgrade scripts (used by CI/CD)
    ├── UpgradeUser.s.sol
    ├── UpgradeChallenge.s.sol
    └── ...
```

## Example Workflow

1. Developer modifies `src/User.sol` to add a new feature
2. Developer commits and pushes to `main` branch
3. GitHub Action detects change in `User.sol`
4. Workflow runs tests to ensure everything passes
5. Workflow executes `script/upgrade/UpgradeUser.s.sol`
6. New implementation deployed and verified on Etherscan
7. Proxy upgraded to point to new implementation
8. Deployment config automatically committed back to repo
9. Users continue using the same proxy address with new functionality

## Troubleshooting

### Deployment fails
- Check that all GitHub secrets are configured correctly
- Ensure the deployer wallet has sufficient ETH for gas
- Verify that tests pass locally: `forge test`

### Proxy address not found
- Ensure initial deployment was completed: `forge script script/Deploy.s.sol --rpc-url sepolia --broadcast`
- Check that `deployments/sepolia.json` exists and contains proxy addresses

### Contract verification fails
- Verify `ETHERSCAN_API_KEY` is valid
- Verification can be done manually later: `forge verify-contract <address> <contract> --chain sepolia`
