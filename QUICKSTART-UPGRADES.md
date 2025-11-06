# Quick Start: Modular Upgradeable Deployment

## TL;DR - What You Can Do Now

```bash
# Deploy everything at once
just deploy-local

# Deploy just one contract
just deploy Poll local

# Upgrade just one contract (preserves address & data!)
just upgrade Poll local

# Check what's deployed
cat deployments/anvil.json
```

## Common Workflows

### 1. Fresh Start - Deploy Everything

```bash
# Terminal 1: Start local blockchain
forge anvil

# Terminal 2: Deploy all contracts
just deploy-local
```

**Result:** All 6 contracts deployed with proxies, addresses in `deployments/anvil.json`

---

### 2. Fix a Bug in One Contract

Let's say you found a bug in `Poll.sol`:

```bash
# 1. Fix the bug in src/Poll.sol
vim src/Poll.sol

# 2. Test it
forge test

# 3. Upgrade ONLY Poll (not everything!)
just upgrade Poll local
```

**Result:**
- ✅ Poll contract updated with new logic
- ✅ Same address (proxy address unchanged)
- ✅ All polls, votes, data preserved
- ✅ No need to redeploy other 5 contracts!

---

### 3. Add a New Feature to One Contract

You want to add a new function to `User.sol`:

```bash
# 1. Add your new function to src/User.sol
# (Make sure you add storage variables at the END)

# 2. Test it
forge test

# 3. Upgrade User
just upgrade User local
```

**Result:** New function available, all existing users and data intact

---

### 4. Deploy to Testnet

```bash
# Deploy everything to Sepolia
just deploy-sepolia

# Or upgrade one contract on Sepolia
just upgrade Poll sepolia
```

**Result:** Deployed/upgraded on Sepolia with Etherscan verification

---

## File Structure

```
trust-me-contracts/
├── src/                          # Your contracts (now upgradeable!)
│   ├── TopicRegistry.sol
│   ├── User.sol
│   ├── Challenge.sol
│   ├── PeerRating.sol
│   ├── ReputationEngine.sol
│   └── Poll.sol
│
├── script/
│   ├── Deploy.s.sol              # Orchestrates full deployment
│   │
│   ├── config/
│   │   └── DeploymentConfig.sol  # Manages addresses
│   │
│   ├── deploy/                   # Individual deploy scripts
│   │   ├── DeployTopicRegistry.s.sol
│   │   ├── DeployUser.s.sol
│   │   ├── DeployChallenge.s.sol
│   │   ├── DeployPeerRating.s.sol
│   │   ├── DeployReputationEngine.s.sol
│   │   └── DeployPoll.s.sol
│   │
│   └── upgrade/                  # Individual upgrade scripts
│       ├── UpgradeTopicRegistry.s.sol
│       ├── UpgradeUser.s.sol
│       ├── UpgradeChallenge.s.sol
│       ├── UpgradePeerRating.s.sol
│       ├── UpgradeReputationEngine.s.sol
│       └── UpgradePoll.s.sol
│
├── deployments/                  # Auto-generated address configs
│   ├── anvil.json
│   ├── sepolia.json
│   └── mainnet.json
│
├── justfile                      # All your new commands!
├── UPGRADES.md                   # Detailed documentation
└── QUICKSTART-UPGRADES.md        # This file
```

---

## Available Commands

### Full Deployments
```bash
just deploy-local      # Deploy all to local Anvil
just deploy-sepolia    # Deploy all to Sepolia testnet
```

### Individual Contract Deployment
```bash
just deploy <ContractName> <network>
```

### Contract Upgrades
```bash
just upgrade <ContractName> <network>
```

### Other Useful Commands
```bash
forge test              # Run tests
forge build             # Build contracts
forge fmt               # Format code
just --list            # See all commands
```

---

## Key Benefits

### Before (Monolithic Deployment)
❌ Change 1 contract → Redeploy all 6 contracts
❌ Addresses change every deployment
❌ Lose all data (users, challenges, polls)
❌ Waste gas redeploying unchanged contracts
❌ Break frontend integrations

### After (Modular Upgradeable)
✅ Change 1 contract → Upgrade only that 1
✅ Addresses never change (proxy pattern)
✅ Keep all data across upgrades
✅ Save gas - deploy only what changed
✅ Frontend keeps working (same addresses)

---

## Safety Checklist for Upgrades

Before upgrading a contract in production:

- [ ] All tests pass
- [ ] No storage layout changes (don't reorder variables)
- [ ] New variables added at the END only
- [ ] Tested on local/testnet first
- [ ] Reviewed by team
- [ ] Understand the change is permanent

---

## Quick Reference: Deployment Order

Contracts have dependencies. Deploy in this order for individual deployments:

1. **TopicRegistry** (no dependencies)
2. **User** (needs TopicRegistry)
3. **Challenge** (needs TopicRegistry, User)
4. **PeerRating** (needs TopicRegistry, User)
5. **ReputationEngine** (needs User, Challenge, TopicRegistry)
6. **Poll** (needs User, ReputationEngine, TopicRegistry)

The full `just deploy-local` handles this automatically.

---

## Example: End-to-End Workflow

```bash
# 1. Start fresh local node
anvil

# 2. Deploy everything (in another terminal)
just deploy-local

# 3. Verify deployment
cat deployments/anvil.json

# 4. Make changes to Poll.sol
vim src/Poll.sol

# 5. Test your changes
forge test

# 6. Upgrade just Poll
just upgrade Poll local

# 7. Done! Poll has new logic, same address, all data intact
```

---

## Need More Details?

See **UPGRADES.md** for:
- Detailed architecture explanation
- Storage layout rules
- Troubleshooting guide
- Security considerations
- OpenZeppelin documentation links

---

**You now have a production-ready, modular, upgradeable contract deployment system!** 🎉
