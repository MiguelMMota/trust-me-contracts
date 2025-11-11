#!/bin/bash

# Script to update contract addresses in the dapp after deployment
# Usage: ./update-dapp-addresses.sh <network>
# Example: ./update-dapp-addresses.sh anvil

set -e

NETWORK=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_FILE="$CONTRACT_DIR/deployments/$NETWORK.json"
DAPP_CONTRACTS_FILE="$CONTRACT_DIR/../trust-me-dapp/lib/contracts.ts"

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

# Check if dapp contracts file exists
if [ ! -f "$DAPP_CONTRACTS_FILE" ]; then
    echo "Warning: Dapp contracts file not found: $DAPP_CONTRACTS_FILE"
    exit 0
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
echo "TopicRegistry: $TOPIC_REGISTRY"
echo "User: $USER"
echo "Challenge: $CHALLENGE"
echo "PeerRating: $PEER_RATING"
echo "ReputationEngine: $REPUTATION_ENGINE"
echo "Poll: $POLL"

# Create a temporary file with updated addresses
cat > /tmp/contracts_update.txt << EOF
  $CHAIN_ID: {
    Challenge: '$CHALLENGE',
    PeerRating: '$PEER_RATING',
    Poll: '$POLL',
    ReputationEngine: '$REPUTATION_ENGINE',
    TopicRegistry: '$TOPIC_REGISTRY',
    User: '$USER',
  },
EOF

# Use awk to replace the section for this chain ID
awk -v chainid="$CHAIN_ID" -v newcontent="$(cat /tmp/contracts_update.txt)" '
BEGIN { in_section=0; printed=0 }
{
    if ($0 ~ "^  " chainid ": \\{") {
        in_section=1
        print newcontent
        printed=1
        next
    }
    if (in_section && $0 ~ "^  \\},") {
        in_section=0
        next
    }
    if (!in_section) {
        print
    }
}
' "$DAPP_CONTRACTS_FILE" > /tmp/contracts_temp.ts

# Replace the original file
mv /tmp/contracts_temp.ts "$DAPP_CONTRACTS_FILE"
rm -f /tmp/contracts_update.txt

echo "=============================================="
echo "Dapp contract addresses updated successfully!"
echo "=============================================="
