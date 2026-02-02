# Sealed Secrets for Tazama

Sealed Secrets provide a way to store encrypted Kubernetes Secrets in Git safely. The controller running in your cluster can decrypt them, but the encrypted values are safe to commit to version control.

## Prerequisites

1. **Sealed Secrets Controller** must be installed in your cluster
2. **kubeseal CLI** must be installed on your machine

## Installation

### 1. Deploy Sealed Secrets Controller

The controller is managed by ArgoCD:

```bash
# Apply the sealed-secrets application
kubectl apply -f k8s/sealed-secrets/controller-application.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sealed-secrets -n kube-system --timeout=300s
```

### 2. Install kubeseal CLI

**macOS:**
```bash
brew install kubeseal
```

**Linux:**
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.25.0/kubeseal-0.25.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.25.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**Verify:**
```bash
kubeseal --version
```

## Creating Sealed Secrets

### Method 1: Using the Helper Script (Recommended)

We provide a helper script that streamlines the process:

```bash
./scripts/seal-secret.sh
```

The script will prompt you for:
- Secret name
- Namespace
- Key-value pairs

### Method 2: Manual Process

#### Step 1: Create a regular Kubernetes Secret (DON'T commit!)

```bash
kubectl create secret generic tazama-db-credentials \
  --from-literal=POSTGRES_USER=tazama_user \
  --from-literal=POSTGRES_PASSWORD=secure_password_here \
  --namespace=staging \
  --dry-run=client \
  -o yaml > temp-secret.yaml
```

#### Step 2: Seal the secret

```bash
kubeseal --format=yaml \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller \
  < temp-secret.yaml > sealed-db-credentials.yaml
```

#### Step 3: Commit the sealed secret

```bash
# Move to appropriate location
mv sealed-db-credentials.yaml k8s/overlays/staging/

# Commit (safe because it's encrypted!)
git add k8s/overlays/staging/sealed-db-credentials.yaml
git commit -m "Add sealed database credentials"

# Delete the temp file (contains plaintext!)
rm temp-secret.yaml
```

#### Step 4: Reference in Kustomization

Add to your `k8s/overlays/staging/kustomization.yaml`:

```yaml
resources:
  - sealed-db-credentials.yaml
```

## Using Sealed Secrets in Deployments

Once the SealedSecret is created, the controller automatically creates a regular Secret with the same name. Your deployments can reference it normally:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  template:
    spec:
      containers:
        - name: my-service
          envFrom:
            - secretRef:
                name: tazama-db-credentials  # References the unsealed secret
```

## Common Secrets for Tazama

### Database Credentials

```bash
kubectl create secret generic tazama-db-credentials \
  --from-literal=POSTGRES_HOST=postgres-postgresql.infrastructure.svc.cluster.local \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DATABASE=tazama \
  --from-literal=POSTGRES_USER=tazama \
  --from-literal=POSTGRES_PASSWORD=YOUR_SECURE_PASSWORD \
  --namespace=staging \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > k8s/overlays/staging/sealed-db-credentials.yaml
```

### NATS Credentials

```bash
kubectl create secret generic tazama-nats-credentials \
  --from-literal=NATS_URL=nats://nats.infrastructure.svc.cluster.local:4222 \
  --from-literal=NATS_USER=tazama \
  --from-literal=NATS_PASSWORD=YOUR_SECURE_PASSWORD \
  --namespace=staging \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > k8s/overlays/staging/sealed-nats-credentials.yaml
```

## Backup and Restore

### Backup Master Key (CRITICAL!)

```bash
# Backup the master key
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml

# Store this file in a SECURE location (NOT in Git!)
# Examples: AWS Secrets Manager, 1Password, encrypted drive
```

### Restore Master Key

If you need to restore the cluster or move to a new cluster:

```bash
# Apply the backed-up key
kubectl apply -f sealed-secrets-master-key-backup.yaml

# Restart the controller to pick up the key
kubectl rollout restart deployment sealed-secrets-controller -n kube-system
```

## Troubleshooting

### Secret not being created

Check controller logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Certificate errors

Fetch the current certificate:
```bash
kubeseal --fetch-cert \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller
```

### Can't decrypt old secrets

This usually means the master key was lost. You'll need to:
1. Create new secrets
2. Seal them with the new key
3. Update all SealedSecret resources

## Security Best Practices

1. ✅ **DO** commit SealedSecrets to Git
2. ✅ **DO** backup the master key securely
3. ✅ **DO** rotate secrets regularly
4. ❌ **DON'T** commit regular Secrets
5. ❌ **DON'T** commit the master key to Git
6. ❌ **DON'T** lose the master key backup

## More Information

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Official Documentation](https://sealed-secrets.netlify.app/)
