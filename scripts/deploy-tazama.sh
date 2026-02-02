#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Tazama Complete Deployment Script
#
# This script provides an end-to-end deployment of Tazama
# from cluster creation to application deployment.
#
# Usage:
#   ./scripts/deploy-tazama.sh [options]
#
# Options:
#   --skip-cluster        Skip cluster creation
#   --skip-infrastructure Skip infrastructure deployment
#   --skip-applications   Skip application deployment
#   --dry-run            Show what would be done without executing
#   --help               Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default options
SKIP_CLUSTER=false
SKIP_INFRASTRUCTURE=false
SKIP_APPLICATIONS=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-cluster)
      SKIP_CLUSTER=true
      shift
      ;;
    --skip-infrastructure)
      SKIP_INFRASTRUCTURE=true
      shift
      ;;
    --skip-applications)
      SKIP_APPLICATIONS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --skip-cluster        Skip cluster creation"
      echo "  --skip-infrastructure Skip infrastructure deployment"
      echo "  --skip-applications   Skip application deployment"
      echo "  --dry-run            Show what would be done"
      echo "  --help               Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Load environment variables
if [ -f "$REPO_ROOT/.env" ]; then
  echo -e "${BLUE}Loading environment from .env...${NC}"
  set -a
  source "$REPO_ROOT/.env"
  set +a
else
  echo -e "${YELLOW}⚠️  No .env file found. Using defaults or prompting for values.${NC}"
fi

# Default values
AWS_REGION=${AWS_REGION:-us-east-2}
CLUSTER_NAME=${CLUSTER_NAME:-tazama-eks}
TERRAFORM_DIR="$REPO_ROOT/terraform-scripts/eks-terraform"

#####################################
# Helper Functions
#####################################

print_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_step() {
  echo -e "${CYAN}▶${NC} $1"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

check_command() {
  if ! command -v $1 &> /dev/null; then
    print_error "$1 is not installed"
    echo -e "Install it from: $2"
    exit 1
  fi
}

execute_or_dry_run() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would execute: $1${NC}"
  else
    eval "$1"
  fi
}

wait_for_pods() {
  local namespace=$1
  local label=$2
  local timeout=${3:-300}

  print_step "Waiting for pods in namespace $namespace with label $label..."
  if [ "$DRY_RUN" = false ]; then
    kubectl wait --for=condition=ready pod \
      -l "$label" \
      -n "$namespace" \
      --timeout="${timeout}s" || print_warning "Some pods may not be ready yet"
  fi
}

#####################################
# Validation
#####################################

validate_prerequisites() {
  print_header "Validating Prerequisites"

  print_step "Checking required tools..."
  check_command kubectl "https://kubernetes.io/docs/tasks/tools/"
  check_command helm "https://helm.sh/docs/intro/install/"
  check_command terraform "https://learn.hashicorp.com/tutorials/terraform/install-cli"
  check_command aws "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"

  print_success "All required tools are installed"

  # Check AWS credentials
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    print_warning "AWS credentials not set in environment"
    print_step "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity &>/dev/null; then
      print_error "AWS CLI not configured. Run: aws configure"
      exit 1
    fi
  fi

  print_success "AWS credentials validated"
}

#####################################
# Cluster Creation
#####################################

create_cluster() {
  if [ "$SKIP_CLUSTER" = true ]; then
    print_warning "Skipping cluster creation (--skip-cluster)"
    return
  fi

  print_header "Creating EKS Cluster"

  cd "$TERRAFORM_DIR"

  # Check if terraform.tfvars exists
  if [ ! -f terraform.tfvars ]; then
    print_warning "terraform.tfvars not found"
    print_step "Creating from sample..."
    cp sample.terraform.tfvars terraform.tfvars

    if [ "$DRY_RUN" = false ]; then
      print_error "Please edit $TERRAFORM_DIR/terraform.tfvars with your values"
      print_step "Required values:"
      echo "  - aws_access_key"
      echo "  - aws_secret_key"
      echo "  - region"
      exit 1
    fi
  fi

  print_step "Initializing Terraform..."
  execute_or_dry_run "terraform init -reconfigure"

  print_step "Validating Terraform configuration..."
  execute_or_dry_run "terraform validate"

  print_step "Planning infrastructure..."
  if [ "$DRY_RUN" = false ]; then
    terraform plan -out=terraform.plan
  fi

  print_step "Creating EKS cluster (this takes ~15 minutes)..."
  execute_or_dry_run "terraform apply -auto-approve"

  cd "$REPO_ROOT"

  print_success "Cluster created successfully"
}

#####################################
# Kubectl Configuration
#####################################

configure_kubectl() {
  print_header "Configuring kubectl"

  print_step "Updating kubeconfig..."
  execute_or_dry_run "aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME"

  if [ "$DRY_RUN" = false ]; then
    print_step "Verifying cluster connection..."
    kubectl cluster-info
    kubectl get nodes
  fi

  print_success "kubectl configured"
}

#####################################
# ArgoCD Installation
#####################################

install_argocd() {
  print_header "Installing ArgoCD"

  print_step "Creating argocd namespace..."
  execute_or_dry_run "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -"

  print_step "Installing ArgoCD manifests..."
  execute_or_dry_run "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

  print_step "Waiting for ArgoCD to be ready..."
  if [ "$DRY_RUN" = false ]; then
    kubectl wait --for=condition=available \
      --timeout=300s \
      deployment/argocd-server \
      -n argocd
  fi

  print_success "ArgoCD installed"

  if [ "$DRY_RUN" = false ]; then
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  ArgoCD Access Information${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Admin Password:${NC}"
    kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d
    echo ""
    echo ""
    echo -e "${CYAN}Access UI:${NC}"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Then open: https://localhost:8080"
    echo ""
    echo -e "${CYAN}Login:${NC}"
    echo "  Username: admin"
    echo "  Password: (shown above)"
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════${NC}"
    echo ""
  fi
}

#####################################
# Helm Repository Setup
#####################################

setup_helm_repos() {
  print_header "Setting up Helm Repositories"

  if [ -x "$SCRIPT_DIR/setup-helm-repos.sh" ]; then
    execute_or_dry_run "$SCRIPT_DIR/setup-helm-repos.sh"
  else
    print_warning "Helm setup script not found or not executable"
  fi

  print_success "Helm repositories configured"
}

#####################################
# Infrastructure Deployment
#####################################

deploy_infrastructure() {
  if [ "$SKIP_INFRASTRUCTURE" = true ]; then
    print_warning "Skipping infrastructure deployment (--skip-infrastructure)"
    return
  fi

  print_header "Deploying Infrastructure"

  print_step "Deploying infrastructure via ArgoCD..."
  execute_or_dry_run "kubectl apply -f $REPO_ROOT/apps/app-of-apps-infrastructure.yaml"

  print_step "Waiting for infrastructure to initialize (30 seconds)..."
  if [ "$DRY_RUN" = false ]; then
    sleep 30
  fi

  print_step "Waiting for PostgreSQL..."
  wait_for_pods "infrastructure" "app.kubernetes.io/name=postgresql" 600

  print_step "Waiting for NATS..."
  wait_for_pods "infrastructure" "app.kubernetes.io/name=nats" 600

  print_success "Infrastructure deployed"
}

#####################################
# Application Deployment
#####################################

deploy_applications() {
  if [ "$SKIP_APPLICATIONS" = true ]; then
    print_warning "Skipping application deployment (--skip-applications)"
    return
  fi

  print_header "Deploying Tazama Applications"

  print_step "Deploying applications via ArgoCD..."
  execute_or_dry_run "kubectl apply -f $REPO_ROOT/apps/app-of-apps-staging.yaml"

  print_step "Applications deployment initiated"
  print_warning "Applications will sync automatically. Monitor progress in ArgoCD UI."

  if [ "$DRY_RUN" = false ]; then
    echo ""
    echo -e "${CYAN}Monitor deployment:${NC}"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get pods -n staging"
  fi

  print_success "Applications deployment initiated"
}

#####################################
# Deployment Summary
#####################################

show_summary() {
  print_header "Deployment Summary"

  if [ "$DRY_RUN" = false ]; then
    echo -e "${CYAN}Cluster Information:${NC}"
    kubectl cluster-info || print_warning "Could not retrieve cluster info"
    echo ""

    echo -e "${CYAN}ArgoCD Applications:${NC}"
    kubectl get applications -n argocd 2>/dev/null || print_warning "No ArgoCD applications found"
    echo ""

    echo -e "${CYAN}Infrastructure Pods:${NC}"
    kubectl get pods -n infrastructure 2>/dev/null || print_warning "No infrastructure pods found"
    echo ""

    echo -e "${CYAN}Application Pods:${NC}"
    kubectl get pods -n staging 2>/dev/null || print_warning "No application pods found yet"
    echo ""
  fi

  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Deployment Complete!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${CYAN}Next Steps:${NC}"
  echo "  1. Access ArgoCD UI to monitor deployments"
  echo "  2. Configure sealed secrets if needed"
  echo "  3. Set up ingress for external access"
  echo "  4. Configure monitoring dashboards"
  echo ""
  echo -e "${CYAN}Useful Commands:${NC}"
  echo "  kubectl get applications -n argocd"
  echo "  kubectl get pods -n staging"
  echo "  kubectl logs -f <pod-name> -n staging"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo ""
}

#####################################
# Main Execution
#####################################

main() {
  print_header "Tazama Deployment Automation"

  if [ "$DRY_RUN" = true ]; then
    print_warning "Running in DRY RUN mode - no changes will be made"
    echo ""
  fi

  # Execute deployment steps
  validate_prerequisites
  create_cluster
  configure_kubectl
  install_argocd
  setup_helm_repos
  deploy_infrastructure
  deploy_applications
  show_summary
}

# Run main function
main
