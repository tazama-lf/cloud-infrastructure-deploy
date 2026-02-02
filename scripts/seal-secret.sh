#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Sealed Secret Creation Helper
#
# Interactive script to create sealed secrets for Tazama

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sealed Secret Creator${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo -e "${RED}❌ kubeseal not found${NC}"
    echo -e "${YELLOW}Install: brew install kubeseal${NC}"
    exit 1
fi

# Check if sealed-secrets controller is running
if ! kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
    echo -e "${RED}❌ Sealed Secrets controller not found${NC}"
    echo -e "${YELLOW}Deploy it first: kubectl apply -f k8s/sealed-secrets/controller-application.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get inputs
read -p "Secret name: " SECRET_NAME
read -p "Namespace (default: staging): " NAMESPACE
NAMESPACE=${NAMESPACE:-staging}

echo ""
echo -e "${BLUE}Enter key-value pairs (empty key to finish):${NC}"

# Array to store key-value pairs
declare -a KEYS
declare -a VALUES

while true; do
    read -p "Key: " KEY
    if [ -z "$KEY" ]; then
        break
    fi

    read -sp "Value: " VALUE
    echo ""

    KEYS+=("$KEY")
    VALUES+=("$VALUE")
done

if [ ${#KEYS[@]} -eq 0 ]; then
    echo -e "${RED}❌ No key-value pairs provided${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Creating sealed secret...${NC}"

# Create temporary secret
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Build kubectl command
CMD="kubectl create secret generic $SECRET_NAME --namespace=$NAMESPACE --dry-run=client -o yaml"
for i in "${!KEYS[@]}"; do
    CMD="$CMD --from-literal=${KEYS[$i]}=${VALUES[$i]}"
done

# Create and seal
eval "$CMD" > "$TEMP_FILE"

# Output file
OUTPUT_DIR="k8s/overlays/$NAMESPACE"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/sealed-${SECRET_NAME}.yaml"

# Seal it
if kubeseal --format=yaml \
    --controller-namespace=kube-system \
    --controller-name=sealed-secrets-controller \
    < "$TEMP_FILE" > "$OUTPUT_FILE"; then
    echo -e "${GREEN}✅ Sealed secret created: ${OUTPUT_FILE}${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. Review: ${YELLOW}cat $OUTPUT_FILE${NC}"
    echo -e "  2. Add to kustomization.yaml in $OUTPUT_DIR"
    echo -e "  3. Commit: ${YELLOW}git add $OUTPUT_FILE && git commit${NC}"
else
    echo -e "${RED}❌ Failed to create sealed secret${NC}"
    exit 1
fi
