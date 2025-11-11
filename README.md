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
- [just](https://github.com/casey/just) (recommended for handy command aliases). Install on MacOS with `brew install justfile`

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

**Pre-requisite:** the deployment script 

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

A user's score for a particular topic is calculated as 

```
expertise_score = base_score + Σ(challenge_result * difficulty * time_weight)

time_weight:
- Last 30 days: 1.0 (100%)
- 30-60 days: 0.75 (75%)
- 60+ days: 0.5 (50%)

volume_factor = sqrt(total_challenges) * 10 (capped at 200)

final_score = (accuracy% * 0.7) + (normalized_volume * 0.3)
```

### Gas Optimization

- **Storage Packing**: `uint16` for scores, pack multiple values per slot
- **Event-Driven**: Emit events for indexing, compute off-chain when possible
- **Lazy Evaluation**: Compute scores on-demand, cache results
- **Batch Operations**: Support for multiple operations in one transaction

## Integration with Frontend

After deployment, ABIs will be available in:
```
out/Challenge.sol/Challenge.json
out/Poll.sol/PeerRating.json
out/Poll.sol/Poll.json
out/ReputationEngine.sol/ReputationEngine.json
out/TopicRegistry.sol/TopicRegistry.json
out/User.sol/User.json
```

These will be symlinked to the [frontend dapp repository](https://github.com/MiguelMMota/trust-me-dapp) for integration.

## Security Considerations

- All contracts use Solidity 0.8.24 (built-in overflow protection)
- Access control via modifiers (`onlyAdmin`, `onlyOwner`, `onlyRegistered`, `onlyReputationEngine`, )
- One-time contract linking (prevents unauthorized changes)
- Input validation on all external functions
- Reentrancy protection not needed (no external calls with ETH transfers)

## Future improvements

1. New features
   
   a. Teams - restricted access groups
   
   b. Prediction markets - polls with payouts which are affected by participant believability scores.
2. Improvements in the ranking engine
   a. Account for the rater's believability when rating others. This believability may be determined by:
      
      i. account age (ratings from newer accounts are less believable)
      
      ii. rater's own score in the topic. Low ratings should be less believable, but especially when the rater's score is lower than the one they attribute to the ratee
      
      iii. rater behaviour. Consistently overrating other users should make a user's ratings to others less believable
   b. Account for other parameters in the ratee

      i. account age (ratings to newer accounts are less believable)
      
      ii. rating clusters (groups of users that consistently rate each other may be engineering results)
      
      iii. value/volume discrepancy between rate types. E.g.: rate from challenges shouldn't be sustantially lower than rate from peers. It may also be suspicious if a user's rating comes almost exclusively from either challenges or peers.

3. Custom ranking weights. Users may want to  use their own `ReputationEngine` implementation, or customise the weight given to challenges, peer ratings, time decay, etc.

4. Give users the option to reject positive feedback. One of the ways to discourage inflated ratings would be to retro-actively adjust user scores when an inconsistency is detected. If users are allowed to reject positive feedback (e.g.: feedback above their rating), one possible approach is to deliberately overcorrect. This encourages users to reject inflated ratings from others, which in turn encourages users to rate honestly.


## Challenges

1. Some data should be private. E.g.:
   a. teams should have the option to deny/restrict visibility of team data (internal ratings, polls, etc) to users outside the team.
   b. users may want to vote on issues confidentially for a variety of reasons:
     i. not wanting to defend certain potentially sensitive matters of opinion publicly
     ii. honest feedback on coworkers, friends, and family may be unflattering
     iii. users with a high social profile may bias results if their votes are public because other users will adopt their stance by transferrence, essentially giving the popular user an artificially high vote weight
2. Security and balance in prediction markets. Believability-weighted odds in prediction markets are highly susceptible to exploits. Some common attack vectors in Defi protocols attempt to create and exploit imbalances in the underlying token pairs (e.g.: by devaluing a user's collateral) that balance the system. A believability-weighted prediction market would also have to ensure that this balance can't be exploited by abusing the user's own effect on the markets. Here's an example of a possible attack, wherein a user manipulates market odds to guarantee returns from betting both sides of the market:
   
   a. a user quickly grows an account A1 to an extremely high valuation in topic T1 through social engineering, account spamming, cheating in challenges, or other means.
   
   b. the user repeats the process to get an extremely low score on topic T1 in a separate account A2.
   
   c. the user places a 100$ bet on the event "tails" in a small prediction market for a fair coin flip. The user has a high believability score in the market's topics. For the sake of example, let's say the user's vote causes the market to update the odds from 50/50 to 80% tails vs 20% heads﹡. If the "tails" comes, A1 is credited with 125$
   
   d. the user places a bet on the event "heads" in the same market. The effect on the market odds is negligible. If "heads" comes, A2 is credited with 400$.
   
   e. if "tails" comes, the user loses 75$ (125$ - 2 * 100$). If "heads" comes, the user gains 200$ (400$ - 2 * 100$). The EV of the attack is 62.5$.

   *﹡The user must be granted a return based on the odds before they voted. The alternative would be that high-believability users would be disincentivised from participating honestly in markets as their EV would be smaller purely from their influence on the market odds.*