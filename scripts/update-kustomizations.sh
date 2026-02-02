#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Update all kustomization.yaml files to use central version management
#
# This script adds image transformers to all base kustomization files
# so they reference the central versions.yaml file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$REPO_ROOT/k8s/base"

echo "Updating kustomization files with image transformers..."

# Get all services except demo-ui (which uses 'rc' tag)
for service_dir in "$BASE_DIR"/*; do
  if [ -d "$service_dir" ]; then
    service_name=$(basename "$service_dir")
    kustomization_file="$service_dir/kustomization.yaml"

    if [ -f "$kustomization_file" ]; then
      echo "Processing: $service_name"

      # Check if images section already exists
      if grep -q "^images:" "$kustomization_file"; then
        echo "  ⚠️  Images section already exists, skipping"
        continue
      fi

      # Determine the image name and tag
      if [ "$service_name" = "demo-ui" ]; then
        new_tag="rc"
      else
        new_tag="3.0.0"
      fi

      # Add images transformer
      cat >> "$kustomization_file" <<EOF
images:
  - name: tazamaorg/${service_name}
    newTag: ${new_tag}
EOF

      echo "  ✓ Updated"
    fi
  fi
done

echo "✅ All kustomization files updated!"
