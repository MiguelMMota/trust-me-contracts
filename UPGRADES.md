# TrustMe Contracts - Upgradeable Architecture

## Overview

Your TrustMe contracts have been converted to a **modular, upgradeable architecture** using OpenZeppelin's UUPS (Universal Upgradeable Proxy Standard) pattern. This allows you to:

✅ **Deploy individual contracts** without redeploying the entire system
✅ **Upgrade contract logic** without changing addresses or losing state
✅ **Save gas** by only deploying what you need
✅ **Preserve data** across upgrades

## What Changed?

### 1. All Contracts Are Now Upgradeable (UUPS Pattern)

**Converted contracts:**
- TopicRegistry
- User
- Challenge
- PeerRating
- ReputationEngine
- Poll

**Key changes:**
- Constructors → `initialize()` functions
- Added OpenZeppelin imports: `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`
- `immutable` variables → regular state variables
- `admin` → `owner()` (from OwnableUpgradeable)
- Added `_authorizeUpgrade()` for owner-controlled upgrades

### 2. New Deployment Infrastructure

#### **DeploymentConfig.sol** (`script/config/`)
- Manages deployed addresses across networks
- Reads/writes to JSON files in `deployments/`
- Provides helpers: `loadDeployment()`, `saveDeployment()`, `getContractAddress()`

#### **Individual Deployment Scripts** (`script/deploy/`)
Each contract has its own deployment script:
- `DeployTopicRegistry.s.sol`
- `DeployUser.s.sol`
- `DeployChallenge.s.sol`
- `DeployPeerRating.s.sol`
- `DeployReputationEngine.s.sol`
- `DeployPoll.s.sol`

Each script:
1. Deploys the implementation contract
2. Deploys an ERC1967Proxy pointing to the implementation
3. Initializes via the proxy
4. Saves the proxy address to `deployments/{network}.json`

#### **Individual Upgrade Scripts** (`script/upgrade/`)
Each contract has its own upgrade script:
- `UpgradeTopicRegistry.s.sol`
- `UpgradeUser.s.sol`
- `UpgradeChallenge.s.sol`
- `UpgradePeerRating.s.sol`
- `UpgradeReputationEngine.s.sol`
- `UpgradePoll.s.sol`

Each upgrade script:
1. Loads the existing proxy address
2. Deploys a new implementation
3. Calls `upgradeToAndCall()` on the proxy
4. Verifies the upgrade succeeded

## How to Use

### Full System Deployment

Deploy all contracts at once (use for initial deployment or fresh networks):

```bash
# Local (Anvil)
just deploy-local

# Sepolia testnet
just deploy-sepolia
```

This will:
- Deploy all 6 contracts with proxies
- Set up cross-contract references
- Create initial topic hierarchy
- Save addresses to `deployments/{network}.json`

### Deploy Individual Contracts

Deploy a single contract (useful when only one contract changes):

```bash
# Generic command
just deploy-contract <ContractName> <network>

# Examples:
just deploy-contract TopicRegistry local
just deploy-contract User sepolia
just deploy-contract Poll local
```

Or use specific commands:

```bash
just deploy-topic-registry-local
just deploy-user-local
just deploy-challenge-local
just deploy-peer-rating-local
just deploy-reputation-engine-local
just deploy-poll-local
```

**Dependencies:** Contracts with dependencies must have their dependencies deployed first:
- **User** requires TopicRegistry
- **Challenge** requires TopicRegistry + User
- **PeerRating** requires TopicRegistry + User
- **ReputationEngine** requires User + Challenge + TopicRegistry
- **Poll** requires User + ReputationEngine + TopicRegistry

### Upgrade Individual Contracts

When you update a contract's logic, upgrade just that contract:

```bash
# Generic command
just upgrade-contract <ContractName> <network>

# Examples:
just upgrade-contract TopicRegistry local
just upgrade-contract User sepolia
just upgrade-contract Poll local
```

Or use specific commands:

```bash
just upgrade-topic-registry-local
just upgrade-user-local
just upgrade-challenge-local
just upgrade-peer-rating-local
just upgrade-reputation-engine-local
just upgrade-poll-local
```

**Important:** Upgrades preserve:
- ✅ Contract addresses (proxy address stays the same)
- ✅ All contract state (storage remains intact)
- ✅ All existing data (users, challenges, polls, etc.)

## Deployment Flow Examples

### Example 1: Fresh Deployment

```bash
# Start local node
just anvil

# In another terminal, deploy everything
just deploy-local
```

Result: All contracts deployed with proxies, addresses saved to `deployments/anvil.json`

### Example 2: Update Just One Contract

Let's say you fix a bug in the Poll contract:

```bash
# 1. Edit src/Poll.sol
# 2. Test your changes
just test

# 3. Upgrade just the Poll contract
just upgrade-poll-local
```

Result: Poll logic updated, address unchanged, all data preserved

### Example 3: Selective Deployment

You only need to deploy User for testing:

```bash
# 1. Deploy TopicRegistry (dependency)
just deploy-topic-registry-local

# 2. Deploy User
just deploy-user-local
```

Result: Only those 2 contracts deployed, no wasted gas on others

## Deployment Addresses

Deployed addresses are automatically saved to:
```
deployments/
├── anvil.json
├── sepolia.json
└── mainnet.json
```

Each file contains:
```json
{
  "network": "anvil",
  "chainId": 31337,
  "timestamp": 1699564800,
  "topicRegistry": "0x...",
  "user": "0x...",
  "challenge": "0x...",
  "peerRating": "0x...",
  "reputationEngine": "0x...",
  "poll": "0x..."
}
```

## Upgrade Safety

### Before Upgrading

1. **Test thoroughly** - Upgrades are irreversible
2. **Check storage layout** - Don't reorder or remove storage variables
3. **Review carefully** - New implementation must be compatible

### Storage Layout Rules

✅ **Safe:**
- Adding new state variables at the end
- Adding new functions
- Modifying function logic

❌ **Unsafe:**
- Reordering existing state variables
- Changing variable types
- Removing state variables
- Changing inheritance order

### Upgrade Authorization

Only the **owner** of each contract can authorize upgrades via the `_authorizeUpgrade()` function. The owner is set during initialization (typically the deployer address).

## Architecture Diagram

```
┌─────────────────┐
│   Your Code     │
│  (src/*.sol)    │
└────────┬────────┘
         │
         │ Upgraded implementation
         ▼
┌─────────────────┐
│ Implementation  │
│   Contract      │
└────────┬────────┘
         │
         │ delegatecall
         ▼
┌─────────────────┐
│  ERC1967Proxy   │ ◄── This address never changes
│   (Storage)     │     Users interact with this
└─────────────────┘
```

## Next Steps

1. **Test the full deployment:**
   ```bash
   just anvil  # Terminal 1
   just deploy-local  # Terminal 2
   ```

2. **Test individual deployments:**
   ```bash
   just deploy-topic-registry-local
   just deploy-user-local
   ```

3. **Test upgrades:**
   - Make a small change to a contract
   - Run `just upgrade-<contract>-local`
   - Verify the upgrade worked

4. **Deploy to testnet:**
   ```bash
   just deploy-sepolia
   ```

## Troubleshooting

### Error: "TopicRegistry must be deployed first"

**Solution:** Deploy dependencies in order:
1. TopicRegistry
2. User
3. Challenge / PeerRating
4. ReputationEngine
5. Poll

### Error: "Proxy not found"

**Solution:** Deploy the contract before trying to upgrade it.

### Tests Failing

**Expected:** Old tests use the old constructor pattern. You'll need to update tests to use the new initialize pattern with proxies. This is normal and expected after this refactor.

## Resources

- [OpenZeppelin UUPS Proxy](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable)
- [Proxy Upgrade Pattern](https://docs.openzeppelin.com/upgrades-plugins/proxies)

---

**Questions?** Check the individual script files in `script/deploy/` and `script/upgrade/` for implementation details.
