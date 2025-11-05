# Deployment Setup Checklist

Follow these steps to enable automated contract deployment on GitHub.

## Prerequisites

- [ ] Contracts already deployed to Sepolia (with proxies)
- [ ] `deployments/sepolia.json` exists with proxy addresses
- [ ] GitHub repository set up

## GitHub Configuration

### 1. Add Repository Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

Add these three secrets:

| Secret Name | Description | Example |
|------------|-------------|---------|
| `DEPLOYER_PRIVATE_KEY` | Private key of deployment wallet | `0xabc123...` |
| `SEPOLIA_RPC_URL` | Sepolia RPC endpoint | `https://sepolia.infura.io/v3/YOUR-PROJECT-ID` |
| `ETHERSCAN_API_KEY` | Etherscan API key for verification | `ABC123XYZ456...` |

### 2. Verify Workflow File

Ensure `.github/workflows/deploy.yml` exists (already created).

### 3. Test the Pipeline

**Option A: Make a real change**
```bash
# Make a small change to a contract
echo "// Updated" >> src/User.sol

# Commit and push
git add src/User.sol
git commit -m "Test automated deployment"
git push origin main
```

**Option B: Test locally first**
```bash
# Run upgrade script locally
forge script script/upgrade/UpgradeUser.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

## Monitoring Deployments

### View Workflow Runs
1. Go to GitHub repository → Actions tab
2. Select "Deploy Changed Contracts" workflow
3. View logs for each deployment

### Check Deployment Status
```bash
# View current deployment addresses
cat deployments/sepolia.json

# Query implementation address from proxy
cast implementation <PROXY_ADDRESS> --rpc-url sepolia
```

## Contract Mapping

The pipeline maps source files to upgrade scripts:

| Source File | Upgrade Script |
|------------|----------------|
| `src/TopicRegistry.sol` | `script/upgrade/UpgradeTopicRegistry.s.sol` |
| `src/User.sol` | `script/upgrade/UpgradeUser.s.sol` |
| `src/Challenge.sol` | `script/upgrade/UpgradeChallenge.s.sol` |
| `src/PeerRating.sol` | `script/upgrade/UpgradePeerRating.s.sol` |
| `src/ReputationEngine.sol` | `script/upgrade/UpgradeReputationEngine.s.sol` |
| `src/Poll.sol` | `script/upgrade/UpgradePoll.s.sol` |

## Important Notes

✅ **Proxy addresses never change** - Users always interact with the same address
✅ **Only changed contracts are upgraded** - Efficient gas usage
✅ **Tests run before deployment** - Failed tests block deployment
✅ **Automatic verification on Etherscan** - Source code published
✅ **Deployment config auto-committed** - Track upgrades in git

⚠️ **Security Considerations**
- Keep `DEPLOYER_PRIVATE_KEY` secret and secure
- Use a dedicated deployment wallet with minimal funds
- Review upgrade changes carefully before pushing to main
- Consider adding a staging environment (e.g., Sepolia) before mainnet

## Mainnet Deployment

To enable mainnet deployment:

1. Add mainnet secrets:
   - `MAINNET_RPC_URL`
   - Update `DEPLOYER_PRIVATE_KEY` for mainnet wallet

2. Modify `.github/workflows/deploy.yml`:
   ```yaml
   # Change this line:
   --rpc-url sepolia \
   # To:
   --rpc-url mainnet \
   ```

3. Ensure `deployments/mainnet.json` exists

4. **Test thoroughly on testnet first!**
