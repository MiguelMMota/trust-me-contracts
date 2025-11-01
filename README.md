# TrustMe Smart Contracts

Expertise-weighted voting system for decentralized collective decision-making.

## Overview

TrustMe is a blockchain-based platform where users build domain-specific expertise through objective validation challenges. Their voting weight on topics is proportional to their proven expertise, with emphasis on recent accuracy and participation volume.

## Contracts

### Core Contracts

1. **TopicRegistry.sol** - Manages hierarchical topic taxonomy
   - Create and manage topics (e.g., Math → Algebra → Linear Algebra)
   - Parent-child topic relationships
   - Admin controls for topic management

2. **User.sol** - User profiles and expertise tracking
   - User registration
   - Expertise scores per topic (0-1000 scale, starts at 50)
   - Challenge attempt history
   - Stats and achievements

3. **Challenge.sol** - Objective validation questions
   - Create challenges with verifiable correct answers
   - Answer hashing for privacy
   - Difficulty levels (Easy, Medium, Hard, Expert)
   - Challenge statistics

4. **ReputationEngine.sol** - Scoring algorithm
   - Calculate expertise scores: `score = (accuracy * 0.7) + (volume * 0.3)`
   - Time-weighted scoring (recent activity weighted more)
   - Anti-gaming mechanisms
   - Score preview functionality

5. **Poll.sol** - Weighted voting system
   - Create polls with multiple choice options
   - Weighted voting based on expertise
   - Poll lifecycle management
   - Result calculations with percentages

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for ABIs integration with frontend)

### Installation

```bash
# Install Foundry dependencies
forge install

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
```

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vv

# Run specific test
forge test --match-test testWeightedVoting -vvv

# Gas report
forge test --gas-report
```

## Deployment

### Deploy to Sepolia Testnet

1. Get Sepolia ETH from a faucet: https://sepoliafaucet.com/
2. Set up your `.env` file with:
   - `PRIVATE_KEY`: Your wallet private key
   - `SEPOLIA_RPC_URL`: RPC endpoint (Alchemy, Infura, etc.)
   - `ETHERSCAN_API_KEY`: For contract verification

3. Deploy:

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url sepolia --broadcast --verify
```

4. Deployment addresses will be saved to `deployments.md`

### Deploy to Local Network

```bash
# Start Anvil (local testnet)
anvil

# Deploy to local network
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --broadcast
```

## Architecture

### Scoring Algorithm

```
expertise_score = base_score + Σ(challenge_result * difficulty * time_weight)

time_weight:
- Last 30 days: 1.0 (100%)
- 30-60 days: 0.75 (75%)
- 60+ days: 0.5 (50%)

volume_factor = sqrt(total_challenges) * 10 (capped at 200)

final_score = (accuracy% * 0.7) + (normalized_volume * 0.3)
```

### Score Distribution

- New user (0 challenges): 50
- 50% accuracy, 10 challenges: ~380
- 70% accuracy, 50 challenges: ~570
- 90% accuracy, 100 challenges: ~820
- 95%+ accuracy, 200+ challenges: ~950-1000

### Gas Optimization

- **Storage Packing**: `uint16` for scores, pack multiple values per slot
- **Event-Driven**: Emit events for indexing, compute off-chain when possible
- **Lazy Evaluation**: Compute scores on-demand, cache results
- **Batch Operations**: Support for multiple operations in one transaction

## Testing

The test suite covers:
- Topic creation and hierarchy
- User registration and expertise tracking
- Challenge creation and attempts
- Score calculation and time decay
- Poll creation and weighted voting
- Edge cases and access control

## Initial Topics

The deployment script creates these initial topics:

- **Mathematics**
  - Algebra
  - Calculus
- **History**
  - World History
- **Languages**
  - English
  - Spanish
- **Software Engineering**
  - Frontend Development
  - Backend Development
    - Python
  - Blockchain Development

## Integration with Frontend

After deployment, ABIs will be available in:
```
out/TopicRegistry.sol/TopicRegistry.json
out/User.sol/User.json
out/Challenge.sol/Challenge.json
out/ReputationEngine.sol/ReputationEngine.json
out/Poll.sol/Poll.json
```

These will be symlinked to the frontend dapp repository for integration.

## Security Considerations

- All contracts use Solidity 0.8.24 (built-in overflow protection)
- Access control via modifiers (`onlyAdmin`, `onlyReputationEngine`)
- One-time contract linking (prevents unauthorized changes)
- Input validation on all external functions
- Reentrancy protection not needed (no external calls with ETH transfers)

## License

MIT
