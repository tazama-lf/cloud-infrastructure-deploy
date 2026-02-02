<!-- SPDX-License-Identifier: Apache-2.0 --> 

# Tazama Cloud Infrastructure Deploy

Automated deployment system for Tazama (Real-time Antifraud and Money Laundering Monitoring System) using Kubernetes, Terraform, Helm, ArgoCD, and GitOps principles.

## Quick Start

### One-Command Deployment

```bash
# 1. Clone repository
git clone https://github.com/tazama-lf/cloud-infrastructure-deploy
cd cloud-infrastructure-deploy

# 2. Configure environment
cp .env.sample .env
# Edit .env with your AWS credentials

# 3. Deploy everything
make all
```

That's it! The automated system will:
- ✅ Create EKS cluster with Terraform
- ✅ Install ArgoCD
- ✅ Deploy infrastructure (PostgreSQL, NATS, monitoring)
- ✅ Deploy all 46 Tazama microservices

**Deployment time:** ~20 minutes

---

## Documentation

- **[Quick Start & Deployment Guide](docs/DEPLOYMENT.md)** - Detailed deployment instructions
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Sealed Secrets Guide](k8s/sealed-secrets/README.md)** - Secret management

---

## Features

### Automation Tools

- **Makefile** - Idempotent deployment targets (`make all`, `make cluster`, etc.)
- **Deployment Script** - Interactive bash script for step-by-step deployment
- **Version Management** - Centralized version control for all services
- **GitHub Actions** - Automated image updates via workflow
- **Renovate Bot** - Automated dependency updates

### Infrastructure as Code

- **Terraform** - EKS cluster provisioning
- **ArgoCD** - GitOps continuous delivery
- **Kustomize** - Environment-specific configurations
- **Helm** - Infrastructure dependency management
- **Sealed Secrets** - Encrypted secrets in Git

### Monitoring & Observability

- **Prometheus & Grafana** - Metrics and dashboards
- **NATS** - Message streaming
- **PostgreSQL** - v3.0.0 database (replaces ArangoDB)
- **Nginx Ingress** - Load balancing
- **Keycloak** - Identity management (optional)

---

## Deployment Options

### Option 1: Makefile (Recommended)

```bash
make all                    # Complete deployment
make cluster               # Create cluster only
make infrastructure        # Deploy infrastructure only
make applications          # Deploy applications only
make status                # Show deployment status
make update-version VERSION=3.1.0  # Update all services
make destroy               # Clean everything
```

### Option 2: Deployment Script

```bash
./scripts/deploy-tazama.sh                  # Full deployment
./scripts/deploy-tazama.sh --skip-cluster  # Skip cluster creation
./scripts/deploy-tazama.sh --dry-run       # Show what would happen
```

### Option 3: Manual Step-by-Step

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed manual instructions.

---

## 📋 Table of Contents

- [Compatibility Matrix](#compatibility-matrix)
- [Intended Users](#intended-users)
- [Step 1 - Overview](#step-1---overview)
- [Step 2 - Prerequisites](#step-2---prerequisites)
- [Step 3 - Cluster Setup](#step-3---cluster-setup)
- [Step 4 - Install Helm Dependencies](#step-4---install-helm-dependencies)
  - [Add Helm Repositories](#add-helm-repositories)
  - [Install the Added Helm Charts](#install-the-added-helm-charts)
- [Step 5 - Install Argo CD](#step-5---install-argo-cd)
  - [Install Argo CD in the argocd Namespace](#install-argo-cd-in-the-argocd-namespace)
  - [Access the UI](#access-the-ui)
  - [Optional: Install Argo CD CLI](#optional-install-argo-cd-cli)
- [Step 6 - Deploy Tazama Services via Argo CD](#step-6---deploy-tazama-services-via-argo-cd)
  - [Overview: App-of-Apps Pattern](#overview-app-of-apps-pattern)
  - [Apply the Root Application](#apply-the-root-application)
  - [Verify Deployment](#verify-deployment)
- [Step 7 - Updating & Syncing Services after New Releases](#step-7---updating--syncing-services-after-new-releases)
- [Step 8 - Setting Up Ingress](#step-8---setting-up-ingress)
- [Step 9 - FAQ](#step-9---faq)
- [License](#license)

---

## Compatibility Matrix

| Component          | Minimum Version | Recommended Version | Notes |
|--------------------|-----------------|---------------------|-------|
| **Kubernetes**     | `1.29`          | `1.30+`             | Tested on EKS, GKE, AKS |
| **Terraform**      | `1.9.0`         | `1.9.7`             | Pin in workflows with `hashicorp/setup-terraform@v3` |
| **Helm**           | `3.14.0`        | `3.15+`             | Required for `bitnami`, `nats`, `prometheus-community` charts |
| **Argo CD**        | `2.11.0`        | `2.12+`             | App-of-Apps pattern requires `ApplicationSet` support |
| **Kustomize**      | `5.0+` (built-in)| `5.4+`              | Use `kubectl apply -k` or `kustomize build` |
| **kubectl**        | `1.29+`         | Latest stable       | Must match cluster version (±1 minor) |
| **Docker**         | `24.0+`         | `27.0+`             | For local image testing |
| **Argo CD CLI**    | `2.11+`         | Latest              | `brew install argocd` or binary download |
| **Sealed Secrets** | `0.24+`         | `0.25+`             | Optional: for encrypted secrets in Git |

## Intended Users

- DevOps engineers.
- Developers / Engineers.
- Open-source contributors deploying or extending the Tazama microservices.

`This guide also assumes the above users have foundational understanding of Kubernetes concepts e.g pods, namespaces, ingress and other general DevOps tools e.g Docker, Helm and ArgoCD.`

---

### Step 1 - Overview

**Tazama** is an open-source platform for **real-time fraud detection and transaction monitoring**. This repository and guide provide a fully automated GitOps workflow:

- Declarative infrastructure & apps managed via **Argo CD**
- Configuration through **Kustomize overlays** ( e.g `staging`, `prod`)
- Dependency management using **Helm charts**
- Secrets management via **Kubernetes Secrets** (This section will be added later)
- Continuous delivery triggered by **GitHub Actions** (This section will be added later)

---

### Step 2 - Prerequisites

| Tool | Description | Installation |
|------|--------------|----------|
| **kubectl** | CLI for interacting with Kubernetes | [Install guide](https://kubernetes.io/docs/tasks/tools/) |
| **helm** | Package manager for Kubernetes | [Install Helm](https://helm.sh/docs/intro/install/) |
| **kustomize** | Native k8s configuration management | Included in kubectl ≥ v1.14 |
| **Argo CD CLI** (optional) | Manage apps from terminal | [Install Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| **docker** | Verify images locally | [Install Docker](https://docs.docker.com/get-docker/) |
| **Kubernetes cluster** | Cloud (EKS/GKE/AKS) | Check next section `Cluster Setup` |


> Verify your cluster is ready:
```bash
kubectl get nodes
```

---

### Step 3 - Cluster Setup

If you don’t yet have a running kubernetes cluster but have a cloud account on AWS, we have provided terraform scripts for now in this repository to help you set up an EKS cluster. Navigate to the `terraform scripts` -> `eks-terraform` folder and follow steps in the README.md to setup a cluster with the necessary specs that Tazama requires.

- [Link](https://github.com/tazama-lf/cloud-infrastructure-deploy/tree/dev/terraform-scripts) to the terraform scripts. Currently, only EKS scripts exist. AKS and GKE will be added soon.

Once ready, confirm connectivity:

```bash
kubectl cluster-info
kubectl get ns
```

---

### Step 4 - Install Helm Dependencies

Before deploying Tazama apps, install the supporting infrastructure using Helm.

| Dependency | Chart | Purpose |
|-------------|--------|----------|
| **NATS** | `nats/nats` | Messaging backbone |
| **PostgreSQL** | `bitnami/postgresql` | Core transactional database (Required for v3.0.0+) |
| **Keycloak** | `codecentric/keycloakx` | Identity & access management |
| **NGINX Ingress** | `ingress-nginx/ingress-nginx` | Reverse proxy & routing |
| **Prometheus & Grafana** | `prometheus-community/kube-prometheus-stack` | Metrics and dashboards |
| **Elastic Stack (ELK)** | `elastic/helm-charts` | Centralized logging and observability |

> **Important:** Tazama 3.0.0 uses PostgreSQL exclusively. ArangoDB (used in v2.2.0 and earlier) is no longer required.


#### Add Helm Repositories

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add nats https://nats-io.github.io/k8s/helm/charts/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add elastic https://helm.elastic.co
helm repo update
```

#### Install the Added Helm Charts

```bash
# Create a namespace for shared infrastructure
kubectl create namespace infrastructure

# NATS - messaging backbone
helm install nats nats/nats -n infrastructure
# PostgreSQL - main database
helm install postgres bitnami/postgresql -n infrastructure --set global.postgresql.auth.postgresPassword=admin123
# NGINX Ingress - reverse proxy
helm install ingress-nginx ingress-nginx/ingress-nginx -n infrastructure
# Prometheus & Grafana - monitoring stack
helm install monitoring prometheus-community/kube-prometheus-stack -n infrastructure
# Elastic Stack (ELK) - logging and observability
helm install elastic elastic/elastic-stack -n infrastructure
# Keycloak
helm install keycloak codecentric/keycloakx -n infrastructure --set replicas=1
```

> Note: These default installations are suitable for development and testing environments. For production deployments, review and customize each chart’s values.yaml file and enable persistence, authentication, and proper resource limits.

---

### Setting up Sealed-secrets [WIP]

#### Install controller (once)

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

#### Seal a secret

```bash
kubectl create secret generic db-creds \
  --from-literal=password=$POSTGRES_PASSWORD \
  -n staging --dry-run=client -o yaml \
  | kubeseal --format=yaml > k8s/overlays/staging/sealed-db.yaml
```

---

### Step 4.5 - Configure ImagePullSecrets (If Required)

The Tazama images are pulled from `tazamaorg` on Docker Hub. If these images are private or you encounter Docker Hub rate limits, you'll need to configure ImagePullSecrets.

#### Check if ImagePullSecret is Needed

Try pulling an image locally to test:
```bash
docker pull tazamaorg/rule-001:3.0.0
```

If the pull fails with authentication errors, follow these steps:

#### Create Docker Registry Secret

```bash
# Create the staging namespace first
kubectl create namespace staging

# Create the secret
kubectl create secret docker-registry tazama-dockerhub \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-token> \
  --docker-email=<your-email> \
  -n staging
```

#### Add ImagePullSecret to Deployments

If you need to use the secret, add it to each overlay's kustomization file using a patch. For example:

Create `k8s/overlays/staging/common-patches/imagepullsecret-patch.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder
spec:
  template:
    spec:
      imagePullSecrets:
        - name: tazama-dockerhub
```

Then reference it in each service's `kustomization.yaml`.

---

### Step 5 - Install Argo CD

Argo CD is a declarative, GitOps-based continuous delivery tool for Kubernetes. It continuously monitors your Git repository and automatically syncs your manifests to your cluster.

#### Install Argo CD in the argocd Namespace

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Once installed, verify the pods:

```bash
kubectl get pods -n argocd
```

Expected output should include components like:

```bash
argocd-server
argocd-repo-server
argocd-application-controller
argocd-dex-server
```

#### Access the UI

To access the UI locally, port-forward the service:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 & open https://localhost:8080
# Retrieve the initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

```

If not already opened, point your browser to:
https://localhost:8080


```bash
Credentials:
Username: admin
Password: (admin password value retrieved)
```

- **Tip**: Change the default password after first login: `Settings → Accounts → admin → Update Password`

#### Optional: Install Argo CD CLI

If you prefer managing Argo CD from the command line, install the CLI tool:

```bash
# macOS (Homebrew)
brew install argocd
# Linux
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd
```

Verify installation:

```bash
argocd version
```

Then log in using the same credentials:

```bash
argocd login localhost:8080
```

---

### Step 6 - Deploy Tazama Services via Argo CD

Now that Argo CD is installed and running, you can deploy the entire **Tazama Platform** using the **App-of-Apps** pattern — a GitOps best practice for managing multiple Kubernetes applications from a single source of truth.


#### Overview: App-of-Apps Pattern

The **App-of-Apps** pattern allows you to define one `root` Argo CD Application that automatically creates and manages all other microservice apps (`rule-001, rule-002, event-flow, etc.`). This will sync the services into the staging namespace and deploys images from `tazamaorg/*:3.0.0`

> **Note:** Version 3.0.0 introduces PostgreSQL as the primary database, replacing ArangoDB used in earlier versions (2.2.0 and below).

This setup ensures:
- Consistent configuration across environments (staging, production).
- Centralized version control for all manifests.
- Automated, self-healing synchronization from Git.

<p align="center">
  <img src="https://github.com/user-attachments/assets/1940e772-0ae9-45eb-9b28-cee1e8133059" alt="Architecture Diagram" width="600">
</p>


#### Apply the Root Application

To bootstrap your cluster with all Tazama services:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/tazama-lf/cloud-infrastructure-deploy/main/apps/app-of-apps.yaml
```

- Monitor progress by running `kubectl -n argocd get applications` Or open the Argo CD UI → view synced apps.

> The manifest above defines a root Argo CD Application pointing to the [cloud-infrastructure-deploy](https://github.com/tazama-lf/cloud-infrastructure-deploy) repo, which in turn manages all the defined Tazama components. Once the manifest is applied, Argo CD detects the new “App-of-Apps” definition, It clones the repository, creates child applications for each service defined under `apps/` and each child app deploys its manifests from `k8s/base` and environment overlays (`k8s/overlays/staging or prod`)


Verify Applications in Argo CD by checking that your apps have been created and synced
```bash
kubectl get applications -n argocd
```

Expected output:
```bash
NAME             SYNC STATUS   HEALTH STATUS
rule-001         Synced        Healthy
rule-002         Synced        Healthy
etc.
```

> You can also view them in the Argo CD UI:

Open https://localhost:8080 → `Log in` → `Applications Dashboard`

#### Verify Deployment

Check workloads running in the Cluster by running;

```bash
kubectl get pods -n staging
kubectl get svc -n staging
```

---

### Step 7 - Updating & Syncing Services after New Releases

We provide **three automated methods** for updating service versions:

#### Method 1: Update Script (Recommended for manual updates)

```bash
# Update all services to new version
./scripts/update-version.sh 3.1.0

# Review changes
git diff

# Commit and push
git commit -am "chore: bump services to v3.1.0"
git push

# ArgoCD auto-syncs!
```

#### Method 2: Makefile

```bash
# One command to update all services
make update-version VERSION=3.1.0

# Then commit and push
git commit -am "chore: bump to v3.1.0"
git push
```

#### Method 3: GitHub Actions Workflow

For automated PR creation:

1. Go to **Actions** tab in GitHub
2. Select **"Update Tazama Images"** workflow
3. Click **"Run workflow"**
4. Enter new version (e.g., `3.1.0`)
5. Workflow creates PR automatically
6. Review and merge PR
7. ArgoCD syncs automatically

#### Method 4: Renovate Bot (Fully Automated)

Renovate automatically detects new image versions and creates PRs:

- Configured in `.github/renovate.json`
- Runs weekly by default
- Groups updates by type
- See [Renovate Documentation](https://docs.renovatebot.com/)

> **Note:** All methods update the central `k8s/versions.yaml` file and all service kustomization files. ArgoCD detects Git changes and automatically redeploys.

---

### Step 8 - Setting Up Ingress


---

### Step 9 - FAQ

- Qn, Can I deploy only one service?

    `Yes. Sync the individual app in Argo CD or apply its manifest directly.`

- Qn, What if I don’t use Docker Hub?

    `Update image: fields to your preferred registry (e.g. GHCR, ECR, GCR).`

- Qn, Can Helm replace Kustomize?

    `Yes. You can template services with Helm and let Argo CD manage releases. This is the next milestone after a successful E2E testing with Kustomize.`

- Qn, How do I change environment variables?

    `Edit container env: in each service’s deployment under the appropriate overlay.`

---

## License

```bash
<!-- SPDX-License-Identifier: Apache-2.0 -->
```

Tazama is licensed under the Apache 2.0 License.

---
