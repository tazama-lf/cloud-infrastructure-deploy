#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Apply Environment Injection Patch to All Services
#
# This script updates all service kustomization files to inject
# the tazama-config ConfigMap and tazama-secrets Secret

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STAGING_DIR="$REPO_ROOT/k8s/overlays/staging"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Applying Environment Injection to All Services${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create the env injection patch if it doesn't exist
PATCH_FILE="$STAGING_DIR/common-patches/env-injection-patch.yaml"

if [ ! -f "$PATCH_FILE" ]; then
  echo -e "${YELLOW}Creating env-injection-patch.yaml...${NC}"
  cat > "$PATCH_FILE" <<'EOF'
# SPDX-License-Identifier: Apache-2.0
# Environment Injection Patch
# Injects tazama-config ConfigMap and tazama-secrets Secret into all services
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder
spec:
  template:
    spec:
      containers:
        - name: placeholder
          envFrom:
            - configMapRef:
                name: tazama-config
            - secretRef:
                name: tazama-secrets
EOF
  echo -e "${GREEN}✓ Created env-injection-patch.yaml${NC}"
fi

# Update all service kustomization files
count=0
for service_dir in "$STAGING_DIR"/*; do
  if [ -d "$service_dir" ] && [ -f "$service_dir/kustomization.yaml" ]; then
    service_name=$(basename "$service_dir")

    # Skip common-patches directory
    if [ "$service_name" = "common-patches" ]; then
      continue
    fi

    kustomization_file="$service_dir/kustomization.yaml"

    # Check if env-injection-patch is already referenced
    if grep -q "env-injection-patch.yaml" "$kustomization_file"; then
      echo "  ⚠️  $service_name - already has env injection"
      continue
    fi

    echo "  Processing: $service_name"

    # Check if patchesStrategicMerge exists
    if grep -q "^patchesStrategicMerge:" "$kustomization_file"; then
      # Add to existing patchesStrategicMerge
      sed -i '' '/^patchesStrategicMerge:/a\
  - ../../common-patches/env-injection-patch.yaml
' "$kustomization_file"
    else
      # Add new patchesStrategicMerge section
      echo "" >> "$kustomization_file"
      echo "patchesStrategicMerge:" >> "$kustomization_file"
      echo "  - ../../common-patches/env-injection-patch.yaml" >> "$kustomization_file"
    fi

    echo -e "  ${GREEN}✓${NC} Updated $service_name"
    ((count++))
  fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Environment injection applied to $count services${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Review changes: ${YELLOW}git diff k8s/overlays/staging${NC}"
echo -e "  2. Apply ConfigMap: ${YELLOW}kubectl apply -f k8s/overlays/staging/tazama-config.yaml${NC}"
echo -e "  3. Create secrets: ${YELLOW}See docs/POSTGRES-SETUP.md${NC}"
echo -e "  4. Commit changes: ${YELLOW}git commit -am 'feat: add env injection to all services'${NC}"
echo ""
