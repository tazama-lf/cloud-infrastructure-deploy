# Tazama Deployment Guide

Complete guide for deploying Tazama from scratch using automated tools.

## Quick Start

### One-Command Deployment

```bash
# Copy and configure environment
cp .env.sample .env
# Edit .env with your AWS credentials and preferences

# Deploy everything
make all
```

That's it! The Makefile will:
1. Create EKS cluster with Terraform
2. Install ArgoCD
3. Deploy infrastructure (PostgreSQL, NATS, etc.)
4. Deploy Tazama applications

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Methods](#deployment-methods)
  - [Method 1: Makefile (Recommended)](#method-1-makefile-recommended)
  - [Method 2: Deployment Script](#method-2-deployment-script)
  - [Method 3: Manual Step-by-Step](#method-3-manual-step-by-step)
- [Configuration](#configuration)
- [Post-Deployment](#post-deployment)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

Install these tools before deploying:

| Tool | Version | Installation |
|------|---------|--------------|
| **kubectl** | 1.29+ | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **helm** | 3.14+ | [Install Guide](https://helm.sh/docs/intro/install/) |
| **terraform** | 1.9+ | [Install Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli) |
| **aws-cli** | 2.x | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| **make** | Any | Pre-installed on most systems |

### AWS Requirements

- AWS Account with appropriate permissions
- IAM User with:
  - EKS Full Access
  - VPC Full Access
  - EC2 Full Access
  - IAM Policy Creation
- Access Key and Secret Key

### Optional Tools

- **kubeseal** (for Sealed Secrets): `brew install kubeseal`
- **argocd CLI** (for ArgoCD management): `brew install argocd`

---

## Deployment Methods

### Method 1: Makefile (Recommended)

The Makefile provides a clean, idempotent interface for deployment.

#### Full Deployment

```bash
# Complete deployment
make all

# Dry run (see what would happen)
make all DRY_RUN=true
```

#### Partial Deployment

```bash
# Just create cluster
make cluster

# Just deploy infrastructure
make infrastructure

# Just deploy applications
make applications
```

#### Incremental with Validation

```bash
# Create cluster and validate
make cluster
make validate-cluster

# Deploy infrastructure and validate
make infrastructure
make wait-infrastructure
make validate-infrastructure

# Deploy applications
make applications
make validate-applications
```

#### Common Tasks

```bash
# Show deployment status
make status

# Update to new version
make update-version VERSION=3.1.0

# Create sealed secret
make sealed-secret

# Show ArgoCD logs
make logs

# Get help
make help
```

---

### Method 2: Deployment Script

The bash script provides an interactive deployment experience.

#### Full Deployment

```bash
./scripts/deploy-tazama.sh
```

#### Selective Deployment

```bash
# Skip cluster creation (if already exists)
./scripts/deploy-tazama.sh --skip-cluster

# Skip infrastructure (if already deployed)
./scripts/deploy-tazama.sh --skip-infrastructure

# Skip applications
./scripts/deploy-tazama.sh --skip-applications

# Dry run
./scripts/deploy-tazama.sh --dry-run
```

---

### Method 3: Manual Step-by-Step

If you prefer manual control:

#### Step 1: Create Cluster

```bash
cd terraform-scripts/eks-terraform

# Copy and edit terraform.tfvars
cp sample.terraform.tfvars terraform.tfvars
# Edit with your AWS credentials

# Initialize and apply
terraform init -reconfigure
terraform validate
terraform plan -out terraform.plan
terraform apply terraform.plan
```

#### Step 2: Configure kubectl

```bash
aws eks --region us-east-2 update-kubeconfig --name tazama-eks
kubectl cluster-info
```

#### Step 3: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### Step 4: Setup Helm Repositories

```bash
./scripts/setup-helm-repos.sh
```

#### Step 5: Deploy Infrastructure

```bash
kubectl apply -f apps/app-of-apps-infrastructure.yaml

# Wait for infrastructure
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n infrastructure --timeout=600s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nats -n infrastructure --timeout=600s
```

#### Step 6: Deploy Applications

```bash
kubectl apply -f apps/app-of-apps-staging.yaml
```

---

## Configuration

### Environment Variables

Copy `.env.sample` to `.env` and configure:

```bash
cp .env.sample .env
```

Key configurations:

```bash
# AWS
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-2

# Cluster
CLUSTER_NAME=tazama-eks
NODE_INSTANCE_TYPE=m5.xlarge
NODE_DESIRED_SIZE=3

# Database
POSTGRES_PASSWORD=your_secure_password

# NATS
NATS_PASSWORD=your_secure_password

# Versions
TAZAMA_VERSION=3.0.0
DEMO_UI_VERSION=rc
```

### Deployment Configuration

Edit `config/deployment-config.yaml` for environment-specific settings:

- Resource limits
- Replica counts
- Enabled services
- Infrastructure versions

---

## Post-Deployment

### 1. Access ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser
open https://localhost:8080

# Login
# Username: admin
# Password: (from earlier step)
```

### 2. Configure Sealed Secrets (Optional but Recommended)

```bash
# Install controller (if not using app-of-apps-infrastructure)
kubectl apply -f k8s/sealed-secrets/controller-application.yaml

# Create a sealed secret
./scripts/seal-secret.sh
```

See [k8s/sealed-secrets/README.md](../k8s/sealed-secrets/README.md) for details.

### 3. Verify Deployment

```bash
# Check applications
kubectl get applications -n argocd

# Check infrastructure
kubectl get pods -n infrastructure

# Check Tazama services
kubectl get pods -n staging

# Check specific service logs
kubectl logs -f <pod-name> -n staging
```

### 4. Configure Ingress (Optional)

```bash
# Get LoadBalancer external IP
kubectl get svc -n infrastructure ingress-nginx-controller

# Configure DNS to point to the LoadBalancer
# Create Ingress resources for your services
```

### 5. Access Monitoring

```bash
# Grafana
kubectl port-forward -n infrastructure svc/monitoring-grafana 3000:80
open http://localhost:3000
# Default: admin / admin

# Prometheus
kubectl port-forward -n infrastructure svc/monitoring-kube-prometheus-prometheus 9090:9090
open http://localhost:9090
```

---

## Updating to New Versions

### Update All Services

```bash
# Using Makefile
make update-version VERSION=3.1.0

# Or using script
./scripts/update-version.sh 3.1.0

# Commit and push
git commit -am "chore: bump to v3.1.0"
git push

# ArgoCD auto-syncs!
```

### Update via GitHub Actions

1. Go to Actions tab in GitHub
2. Select "Update Tazama Images"
3. Click "Run workflow"
4. Enter new version (e.g., 3.1.0)
5. Creates PR automatically
6. Review and merge
7. ArgoCD syncs

---

## Cleanup / Destroy

### Destroy Everything

```bash
# Using Makefile (interactive)
make destroy

# Or using script
cd terraform-scripts/eks-terraform
terraform destroy -auto-approve
```

### Destroy Selectively

```bash
# Just applications
make destroy-applications

# Just infrastructure
make destroy-infrastructure

# Just cluster
make destroy-cluster
```

---

## Next Steps

- Configure [Sealed Secrets](../k8s/sealed-secrets/README.md)
- Set up [CI/CD Automation](.github/workflows/update-images.yml)
- Enable [Renovate](../.github/renovate.json) for automated updates
- Review [Troubleshooting](TROUBLESHOOTING.md)
- Read [ANALYSIS-AND-RECOMMENDATIONS.md](../ANALYSIS-AND-RECOMMENDATIONS.md)

---

## Support

- **Issues**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Configuration**: See `.env.sample` and `config/deployment-config.yaml`
- **Sealed Secrets**: See [k8s/sealed-secrets/README.md](../k8s/sealed-secrets/README.md)
- **Version Updates**: See [scripts/update-version.sh](../scripts/update-version.sh)
