#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Helm Repository Setup Script
# Idempotent script to configure all required Helm repositories for Tazama deployment
#
# Usage: ./scripts/setup-helm-repos.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Tazama Helm Repository Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm is not installed${NC}"
    echo -e "${YELLOW}Please install helm: https://helm.sh/docs/intro/install/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Helm $(helm version --short) detected${NC}"
echo ""

# Function to add or update a Helm repository
add_repo() {
  local name=$1
  local url=$2
  local description=$3

  echo -e "${BLUE}➜${NC} Processing repository: ${YELLOW}${name}${NC}"

  if helm repo list 2>/dev/null | grep -q "^${name}[[:space:]]"; then
    echo -e "  ${GREEN}✓${NC} Repository '${name}' already exists"
    echo -e "  ${BLUE}↻${NC} Updating repository..."
    if helm repo update "${name}" &>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Updated successfully"
    else
      echo -e "  ${YELLOW}⚠${NC}  Update failed (repository may be unavailable)"
    fi
  else
    echo -e "  ${BLUE}+${NC} Adding repository..."
    if helm repo add "${name}" "${url}" &>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Added successfully"
    else
      echo -e "  ${RED}✗${NC} Failed to add repository"
      return 1
    fi
  fi
  echo ""
}

echo -e "${BLUE}Adding required Helm repositories...${NC}"
echo ""

# Add all required repositories for Tazama deployment
add_repo "bitnami" \
  "https://charts.bitnami.com/bitnami" \
  "Bitnami charts for PostgreSQL and other infrastructure"

add_repo "nats" \
  "https://nats-io.github.io/k8s/helm/charts/" \
  "NATS messaging system"

add_repo "prometheus-community" \
  "https://prometheus-community.github.io/helm-charts" \
  "Prometheus and Grafana monitoring stack"

add_repo "ingress-nginx" \
  "https://kubernetes.github.io/ingress-nginx" \
  "NGINX Ingress Controller"

add_repo "elastic" \
  "https://helm.elastic.co" \
  "Elastic Stack for logging"

add_repo "codecentric" \
  "https://codecentric.github.io/helm-charts" \
  "Keycloak identity and access management"

add_repo "sealed-secrets" \
  "https://bitnami-labs.github.io/sealed-secrets" \
  "Sealed Secrets for GitOps-friendly secret management"

add_repo "argo" \
  "https://argoproj.github.io/argo-helm" \
  "ArgoCD for GitOps continuous delivery"

# Update all repositories
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Updating all repositories...${NC}"
echo ""

if helm repo update; then
  echo -e "${GREEN}✅ All repositories updated successfully${NC}"
else
  echo -e "${YELLOW}⚠️  Some repositories failed to update (this may be normal)${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Helm repository setup complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# List all repositories
echo -e "${BLUE}Configured repositories:${NC}"
helm repo list

echo ""
echo -e "${BLUE}💡 Tip: Run 'helm search repo <keyword>' to search for charts${NC}"
echo -e "${BLUE}   Example: helm search repo postgresql${NC}"
echo ""
