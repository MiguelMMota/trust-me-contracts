#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if network argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Network not specified${NC}"
    echo "Usage: ./script/verify-proxies.sh <network>"
    echo "Example: ./script/verify-proxies.sh sepolia"
    exit 1
fi

NETWORK=$1
DEPLOYMENT_FILE="deployments/${NETWORK}.json"

# Check if deployment file exists
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo -e "${RED}Error: Deployment file not found: $DEPLOYMENT_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Verifying Proxies on ${NETWORK}${NC}"
echo -e "${BLUE}========================================${NC}"

# Read addresses from deployment file
TOPIC_REGISTRY=$(jq -r '.topicRegistry' "$DEPLOYMENT_FILE")
USER=$(jq -r '.user' "$DEPLOYMENT_FILE")
CHALLENGE=$(jq -r '.challenge' "$DEPLOYMENT_FILE")
PEER_RATING=$(jq -r '.peerRating' "$DEPLOYMENT_FILE")
REPUTATION_ENGINE=$(jq -r '.reputationEngine' "$DEPLOYMENT_FILE")
POLL=$(jq -r '.poll' "$DEPLOYMENT_FILE")

# Set network-specific RPC URL
if [ "$NETWORK" = "sepolia" ]; then
    RPC_URL="$SEPOLIA_RPC_URL"
    EXPLORER_URL="https://sepolia.etherscan.io"
elif [ "$NETWORK" = "mainnet" ]; then
    RPC_URL="$MAINNET_RPC_URL"
    EXPLORER_URL="https://etherscan.io"
else
    echo -e "${RED}Unsupported network: $NETWORK${NC}"
    exit 1
fi

echo -e "\n${GREEN}Checking proxy verification status...${NC}\n"

# Function to check and guide proxy verification
verify_proxy_status() {
    local name=$1
    local address=$2

    echo -e "${BLUE}Checking $name at $address${NC}"

    # Try to get the implementation address to verify it's a proxy
    impl=$(cast implementation "$address" --rpc-url "$RPC_URL" 2>/dev/null || echo "")

    if [ -z "$impl" ]; then
        echo -e "${RED}  ⚠ Could not read implementation (might not be verified as proxy)${NC}"
    else
        echo -e "${GREEN}  ✓ Implementation: $impl${NC}"
    fi

    echo -e "  View on explorer: ${EXPLORER_URL}/address/${address}#code"
    echo ""
}

# Check all proxies
verify_proxy_status "TopicRegistry" "$TOPIC_REGISTRY"
verify_proxy_status "User" "$USER"
verify_proxy_status "Challenge" "$CHALLENGE"
verify_proxy_status "PeerRating" "$PEER_RATING"
verify_proxy_status "ReputationEngine" "$REPUTATION_ENGINE"
verify_proxy_status "Poll" "$POLL"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Manual Verification Instructions${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "\nIf any proxies show warnings, verify them manually on Etherscan:"
echo -e "1. Go to the proxy contract on Etherscan"
echo -e "2. Click 'Contract' tab → 'More Options' → 'Is this a proxy?'"
echo -e "3. Click 'Verify' and Etherscan should auto-detect the proxy"
echo -e "\nAlternatively, if implementations are verified, Etherscan may"
echo -e "automatically detect and verify proxies within a few minutes."
echo -e "\n${GREEN}Done!${NC}\n"
