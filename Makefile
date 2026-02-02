# SPDX-License-Identifier: Apache-2.0
# Makefile for Tazama Deployment Automation
#
# Usage:
#   make all              - Complete deployment (cluster + infrastructure + apps)
#   make cluster          - Create EKS cluster
#   make infrastructure   - Deploy infrastructure (PostgreSQL, NATS, etc.)
#   make applications     - Deploy Tazama services
#   make destroy          - Destroy everything
#   make validate         - Validate deployment
#
# Environment variables can be set in .env file or passed directly

.PHONY: help all cluster infrastructure applications validate destroy clean

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Load environment variables from .env if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Default values
AWS_REGION ?= us-east-2
CLUSTER_NAME ?= tazama-eks
TERRAFORM_DIR := terraform-scripts/eks-terraform
DRY_RUN ?= false

##@ General

help: ## Display this help
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)  Tazama Deployment Automation$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Deployment

all: validate-prereqs cluster configure-kubectl install-argocd infrastructure wait-infrastructure applications validate ## Complete end-to-end deployment

cluster: validate-prereqs ## Create EKS cluster with Terraform
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Creating EKS Cluster: $(CLUSTER_NAME)$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@cd $(TERRAFORM_DIR) && \
		if [ ! -f terraform.tfvars ]; then \
			echo "$(YELLOW)⚠️  Creating terraform.tfvars from sample...$(NC)"; \
			cp sample.terraform.tfvars terraform.tfvars; \
			echo "$(RED)❌ Please edit terraform.tfvars with your AWS credentials$(NC)"; \
			exit 1; \
		fi
	@cd $(TERRAFORM_DIR) && terraform init -reconfigure
	@cd $(TERRAFORM_DIR) && terraform validate
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "$(YELLOW)DRY RUN: Would run terraform plan$(NC)"; \
		cd $(TERRAFORM_DIR) && terraform plan; \
	else \
		cd $(TERRAFORM_DIR) && terraform apply -auto-approve; \
	fi
	@echo "$(GREEN)✅ Cluster created successfully$(NC)"

configure-kubectl: ## Configure kubectl to use the EKS cluster
	@echo "$(BLUE)Configuring kubectl...$(NC)"
	@aws eks --region $(AWS_REGION) update-kubeconfig --name $(CLUSTER_NAME)
	@kubectl cluster-info
	@echo "$(GREEN)✅ kubectl configured$(NC)"

install-argocd: ## Install ArgoCD
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Installing ArgoCD$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "$(BLUE)Waiting for ArgoCD to be ready...$(NC)"
	@kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	@echo "$(GREEN)✅ ArgoCD installed$(NC)"
	@echo ""
	@echo "$(BLUE)ArgoCD admin password:$(NC)"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""
	@echo ""
	@echo "$(BLUE)Access ArgoCD UI:$(NC) kubectl port-forward svc/argocd-server -n argocd 8080:443"

setup-helm-repos: ## Setup Helm repositories
	@echo "$(BLUE)Setting up Helm repositories...$(NC)"
	@./scripts/setup-helm-repos.sh
	@echo "$(GREEN)✅ Helm repositories configured$(NC)"

infrastructure: setup-helm-repos ## Deploy infrastructure (PostgreSQL, NATS, monitoring, etc.)
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Deploying Infrastructure$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "$(YELLOW)DRY RUN: Would deploy infrastructure via ArgoCD$(NC)"; \
	else \
		kubectl apply -f apps/app-of-apps-infrastructure.yaml; \
		echo "$(GREEN)✅ Infrastructure deployment initiated$(NC)"; \
	fi

wait-infrastructure: ## Wait for infrastructure to be ready
	@echo "$(BLUE)Waiting for infrastructure to be ready...$(NC)"
	@echo "$(BLUE)This may take 5-10 minutes...$(NC)"
	@sleep 30
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n infrastructure --timeout=600s || true
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nats -n infrastructure --timeout=600s || true
	@echo "$(GREEN)✅ Infrastructure is ready$(NC)"

applications: ## Deploy Tazama applications
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Deploying Tazama Applications$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "$(YELLOW)DRY RUN: Would deploy applications via ArgoCD$(NC)"; \
	else \
		kubectl apply -f apps/app-of-apps-staging.yaml; \
		echo "$(GREEN)✅ Application deployment initiated$(NC)"; \
	fi

##@ Validation

validate-prereqs: ## Validate required tools are installed
	@echo "$(BLUE)Validating prerequisites...$(NC)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)❌ kubectl not found$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)❌ helm not found$(NC)"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)❌ terraform not found$(NC)"; exit 1; }
	@command -v aws >/dev/null 2>&1 || { echo "$(RED)❌ aws-cli not found$(NC)"; exit 1; }
	@echo "$(GREEN)✅ All prerequisites installed$(NC)"

validate-cluster: ## Validate cluster is accessible
	@echo "$(BLUE)Validating cluster...$(NC)"
	@kubectl cluster-info
	@kubectl get nodes
	@echo "$(GREEN)✅ Cluster is accessible$(NC)"

validate-infrastructure: ## Validate infrastructure is deployed
	@echo "$(BLUE)Validating infrastructure...$(NC)"
	@kubectl get applications -n argocd
	@kubectl get pods -n infrastructure
	@echo "$(GREEN)✅ Infrastructure validated$(NC)"

validate-applications: ## Validate applications are deployed
	@echo "$(BLUE)Validating applications...$(NC)"
	@kubectl get applications -n argocd
	@kubectl get pods -n staging
	@echo "$(GREEN)✅ Applications validated$(NC)"

validate: validate-cluster validate-infrastructure validate-applications ## Validate entire deployment

##@ Maintenance

update-version: ## Update Tazama version (usage: make update-version VERSION=3.1.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)❌ Please specify VERSION (e.g., make update-version VERSION=3.1.0)$(NC)"; \
		exit 1; \
	fi
	@./scripts/update-version.sh $(VERSION)

sealed-secret: ## Create a sealed secret (interactive)
	@./scripts/seal-secret.sh

##@ PostgreSQL Setup

setup-postgres: ## Initialize PostgreSQL databases
	@echo "$(BLUE)Initializing PostgreSQL databases...$(NC)"
	@kubectl cp k8s/postgres/init-databases.sql infrastructure/postgres-postgresql-0:/tmp/init.sql
	@kubectl exec -it postgres-postgresql-0 -n infrastructure -- psql -U postgres -f /tmp/init.sql
	@echo "$(GREEN)✅ PostgreSQL databases initialized$(NC)"

apply-config: ## Apply Tazama ConfigMap
	@echo "$(BLUE)Applying Tazama configuration...$(NC)"
	@kubectl apply -f k8s/overlays/staging/tazama-config.yaml
	@echo "$(GREEN)✅ Configuration applied$(NC)"

apply-env-injection: ## Add environment injection to all services
	@./scripts/apply-env-injection.sh

postgres-shell: ## Connect to PostgreSQL shell
	@kubectl exec -it postgres-postgresql-0 -n infrastructure -- psql -U postgres

postgres-backup: ## Backup all PostgreSQL databases
	@echo "$(BLUE)Creating PostgreSQL backup...$(NC)"
	@kubectl exec postgres-postgresql-0 -n infrastructure -- \
		pg_dumpall -U postgres > postgres-backup-$$(date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)✅ Backup created$(NC)"

##@ Cleanup

destroy-applications: ## Destroy Tazama applications
	@echo "$(RED)Destroying applications...$(NC)"
	@kubectl delete -f apps/app-of-apps-staging.yaml || true
	@kubectl delete namespace staging --wait=false || true
	@echo "$(YELLOW)✓ Applications destroyed$(NC)"

destroy-infrastructure: ## Destroy infrastructure
	@echo "$(RED)Destroying infrastructure...$(NC)"
	@kubectl delete -f apps/app-of-apps-infrastructure.yaml || true
	@kubectl delete namespace infrastructure --wait=false || true
	@echo "$(YELLOW)✓ Infrastructure destroyed$(NC)"

destroy-argocd: ## Destroy ArgoCD
	@echo "$(RED)Destroying ArgoCD...$(NC)"
	@kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true
	@kubectl delete namespace argocd --wait=false || true
	@echo "$(YELLOW)✓ ArgoCD destroyed$(NC)"

destroy-cluster: ## Destroy EKS cluster
	@echo "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(RED)Destroying EKS Cluster$(NC)"
	@echo "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@read -p "Are you sure you want to destroy the cluster? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	@cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
	@echo "$(YELLOW)✓ Cluster destroyed$(NC)"

destroy: destroy-applications destroy-infrastructure destroy-argocd destroy-cluster ## Destroy everything (use with caution!)

clean: ## Clean local files
	@echo "$(BLUE)Cleaning local files...$(NC)"
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "terraform.tfstate*" -delete 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Clean complete$(NC)"

##@ Information

status: ## Show deployment status
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)Deployment Status$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(YELLOW)Cluster:$(NC)"
	@kubectl cluster-info || echo "$(RED)Not connected$(NC)"
	@echo ""
	@echo "$(YELLOW)ArgoCD Applications:$(NC)"
	@kubectl get applications -n argocd 2>/dev/null || echo "$(RED)ArgoCD not installed$(NC)"
	@echo ""
	@echo "$(YELLOW)Infrastructure Pods:$(NC)"
	@kubectl get pods -n infrastructure 2>/dev/null || echo "$(RED)No infrastructure pods$(NC)"
	@echo ""
	@echo "$(YELLOW)Application Pods:$(NC)"
	@kubectl get pods -n staging 2>/dev/null || echo "$(RED)No application pods$(NC)"

logs: ## Show ArgoCD logs
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

.DEFAULT_GOAL := help
