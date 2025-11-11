#!/bin/bash

# Script to update contract addresses in the dapp after deployment
# Usage: ./update-dapp-addresses.sh <network>
# Example: ./update-dapp-addresses.sh anvil

set -e

NETWORK=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_FILE="$CONTRACT_DIR/deployments/$NETWORK.json"
DAPP_CONTRACTS_FILE="$CONTRACT_DIR/../trust-me-dapp/lib/$NETWORK.ts"

# Check if network argument is provided
if [ -z "$NETWORK" ]; then
    echo "Error: Network argument required"
    echo "Usage: $0 <network>"
    exit 1
fi

# Check if deployment file exists
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

echo "=============================================="
echo "Updating dapp contract addresses for $NETWORK"
echo "=============================================="

# Read addresses from deployment JSON
if command -v jq &> /dev/null; then
    # Use jq if available
    CHAIN_ID=$(jq -r '.chainId' "$DEPLOYMENT_FILE")
    TOPIC_REGISTRY=$(jq -r '.topicRegistry' "$DEPLOYMENT_FILE")
    USER=$(jq -r '.user' "$DEPLOYMENT_FILE")
    CHALLENGE=$(jq -r '.challenge' "$DEPLOYMENT_FILE")
    PEER_RATING=$(jq -r '.peerRating' "$DEPLOYMENT_FILE")
    REPUTATION_ENGINE=$(jq -r '.reputationEngine' "$DEPLOYMENT_FILE")
    POLL=$(jq -r '.poll' "$DEPLOYMENT_FILE")
else
    # Fallback: use grep and sed
    CHAIN_ID=$(grep -o '"chainId": [0-9]*' "$DEPLOYMENT_FILE" | grep -o '[0-9]*')
    TOPIC_REGISTRY=$(grep -o '"topicRegistry": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
    USER=$(grep -o '"user": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
    CHALLENGE=$(grep -o '"challenge": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
    PEER_RATING=$(grep -o '"peerRating": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
    REPUTATION_ENGINE=$(grep -o '"reputationEngine": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
    POLL=$(grep -o '"poll": "[^"]*"' "$DEPLOYMENT_FILE" | cut -d'"' -f4)
fi

echo "Chain ID: $CHAIN_ID"
echo "Challenge: $CHALLENGE"
echo "PeerRating: $PEER_RATING"
echo "Poll: $POLL"
echo "ReputationEngine: $REPUTATION_ENGINE"
echo "TopicRegistry: $TOPIC_REGISTRY"
echo "User: $USER"

# Update dapp contract addresses file
NETWORK_UPPER=$(echo "$NETWORK" | tr '[:lower:]' '[:upper:]')
cat > "$DAPP_CONTRACTS_FILE" << EOF
export const ${NETWORK_UPPER}_CONTRACTS = {
  Challenge: '$CHALLENGE',
  PeerRating: '$PEER_RATING',
  Poll: '$POLL',
  ReputationEngine: '$REPUTATION_ENGINE',
  TopicRegistry: '$TOPIC_REGISTRY',
  User: '$USER',
};
EOF

echo "=============================================="
echo "Dapp contract addresses updated successfully!"
echo "=============================================="
