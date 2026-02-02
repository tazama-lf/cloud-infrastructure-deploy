#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Update Tazama Service Versions
#
# This script updates the version in k8s/versions.yaml and then updates
# all affected kustomization.yaml files

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$REPO_ROOT/k8s/versions.yaml"

# Display usage
usage() {
  echo "Usage: $0 <new_version>"
  echo ""
  echo "Example: $0 3.1.0"
  echo ""
  echo "This will update all Tazama services (except demo-ui) to version 3.1.0"
  exit 1
}

# Check arguments
if [ $# -ne 1 ]; then
  usage
fi

NEW_VERSION=$1

# Validate version format (simple check)
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo -e "${RED}❌ Error: Invalid version format${NC}"
  echo -e "${YELLOW}Version must be in format: X.Y.Z (e.g., 3.1.0)${NC}"
  exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Tazama Version Update${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get current version
CURRENT_VERSION=$(grep "TAZAMA_VERSION:" "$VERSIONS_FILE" | awk '{print $2}' | tr -d '"')
echo -e "${BLUE}Current version:${NC} ${YELLOW}${CURRENT_VERSION}${NC}"
echo -e "${BLUE}New version:${NC}     ${GREEN}${NEW_VERSION}${NC}"
echo ""

# Confirm
read -p "Continue with version update? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Update cancelled${NC}"
  exit 0
fi

echo ""
echo -e "${BLUE}Updating versions.yaml...${NC}"

# Update versions.yaml
sed -i '' "s/TAZAMA_VERSION: \"${CURRENT_VERSION}\"/TAZAMA_VERSION: \"${NEW_VERSION}\"/" "$VERSIONS_FILE"
echo -e "${GREEN}✓${NC} Updated versions.yaml"

# Update all kustomization files (except demo-ui)
echo ""
echo -e "${BLUE}Updating kustomization files...${NC}"

find "$REPO_ROOT/k8s/base" -name "kustomization.yaml" \
  ! -path "*/demo-ui/*" \
  -exec sed -i '' "s/newTag: ${CURRENT_VERSION}/newTag: ${NEW_VERSION}/" {} \;

echo -e "${GREEN}✓${NC} Updated all kustomization files"

# Count updated files
UPDATED_COUNT=$(find "$REPO_ROOT/k8s/base" -name "kustomization.yaml" ! -path "*/demo-ui/*" | wc -l | tr -d ' ')

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Version update complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Updated files:${NC} ${UPDATED_COUNT} kustomization files + 1 versions.yaml"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Review changes: ${YELLOW}git diff${NC}"
echo -e "  2. Commit changes: ${YELLOW}git commit -am 'chore: bump version to ${NEW_VERSION}'${NC}"
echo -e "  3. Push to trigger ArgoCD sync: ${YELLOW}git push${NC}"
echo ""
