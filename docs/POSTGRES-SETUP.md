# PostgreSQL Setup Guide for Tazama v3.0.0

Complete guide for setting up PostgreSQL to replace ArangoDB in Tazama deployment.

## Overview

Tazama v3.0.0 migrated from ArangoDB to PostgreSQL based on the POC at [postgres-poc](https://github.com/tazama-lf/postgres-poc).

### Key Changes from ArangoDB

| Aspect | ArangoDB (v2.2.0) | PostgreSQL (v3.0.0) |
|--------|-------------------|---------------------|
| **Document Storage** | Native JSON documents | JSONB columns + generated fields |
| **Databases** | Multiple databases | Multiple PostgreSQL databases |
| **Query Language** | AQL | SQL |
| **Schema** | Schema-less | Hybrid (JSONB + indexed columns) |
| **REST API** | Built-in | Application-level |

---

## Quick Start

### 1. PostgreSQL is Already Deployed

If you used `make all` or `make infrastructure`, PostgreSQL is already running:

```bash
# Check PostgreSQL status
kubectl get pods -n infrastructure -l app.kubernetes.io/name=postgresql

# Get PostgreSQL password
kubectl get secret postgres-postgresql -n infrastructure \
  -o jsonpath="{.data.postgres-password}" | base64 -d
```

### 2. Initialize Databases

```bash
# Copy initialization script to pod
kubectl cp k8s/postgres/init-databases.sql \
  infrastructure/postgres-postgresql-0:/tmp/init-databases.sql

# Run initialization
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -f /tmp/init-databases.sql
```

### 3. Apply Configuration

```bash
# Apply ConfigMap with connection details
kubectl apply -f k8s/overlays/staging/tazama-config.yaml

# Create sealed secrets (see below)
```

---

## Database Architecture

### Four Databases Created

#### 1. **configuration**
**Purpose:** Network maps, typology expressions, rule configurations

**Tables:**
- `networkMap` - Message routing configuration
- `typologyExpression` - Typology rule definitions

**Connection:**
```
postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/configuration
```

#### 2. **transactionHistory**
**Purpose:** Transaction storage and retrieval

**Tables:**
- `transactions` - Full transaction data in JSONB with generated columns

**Key Features:**
- Full transaction stored as JSONB
- Generated columns for efficient querying (amount, type, parties)
- GIN indexes for fast JSONB searches
- Renamed `to`/`from` to `sender`/`receiver` (SQL reserved words)

**Connection:**
```
postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/transactionHistory
```

#### 3. **pseudonyms**
**Purpose:** Pseudonym generation and lookup for PII protection

**Tables:**
- `pseudonymMappings` - Actual value ↔ pseudonym mappings

**Connection:**
```
postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/pseudonyms
```

#### 4. **evaluations**
**Purpose:** CADProc evaluation results, scores, alerts

**Tables:**
- `transaction_evaluations` - Rule/typology evaluation results

**Connection:**
```
postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/evaluations
```

---

## Creating Secrets

### Method 1: Using Sealed Secrets (Recommended)

```bash
# 1. Edit the template with your passwords
cp k8s/overlays/staging/tazama-secrets-template.yaml temp-secrets.yaml
# Edit temp-secrets.yaml - replace all CHANGE_ME values

# 2. Create sealed secret
kubectl create secret generic tazama-secrets \
  --from-literal=POSTGRES_PASSWORD=your_secure_password \
  --from-literal=CONFIGURATION_DB_PASSWORD=your_secure_password \
  --from-literal=TRANSACTION_HISTORY_DB_PASSWORD=your_secure_password \
  --from-literal=PSEUDONYMS_DB_PASSWORD=your_secure_password \
  --from-literal=EVALUATIONS_DB_PASSWORD=your_secure_password \
  --from-literal=NATS_PASSWORD=your_secure_password \
  --namespace=staging \
  --dry-run=client -o yaml | \
kubeseal --format=yaml \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller \
  > k8s/overlays/staging/sealed-tazama-secrets.yaml

# 3. Apply sealed secret
kubectl apply -f k8s/overlays/staging/sealed-tazama-secrets.yaml

# 4. Delete temp file
rm temp-secrets.yaml

# 5. Commit sealed secret (safe!)
git add k8s/overlays/staging/sealed-tazama-secrets.yaml
git commit -m "Add Tazama sealed secrets"
```

### Method 2: Using Interactive Script

```bash
./scripts/seal-secret.sh
# Follow prompts to create sealed secret
```

---

## Connecting Services to PostgreSQL

### Update Deployment to Use Secrets

Add to your service deployment's `envFrom`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rule-001
spec:
  template:
    spec:
      containers:
        - name: rule-001
          envFrom:
            # Add these two
            - configMapRef:
                name: tazama-config
            - secretRef:
                name: tazama-secrets
```

### Apply to All Services

We can create a common patch for this. Create `k8s/overlays/staging/common-patches/env-injection-patch.yaml`:

```yaml
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
```

Then reference it in each service's `kustomization.yaml`:

```yaml
patchesStrategicMerge:
  - ../../common-patches/env-injection-patch.yaml
  - ../../common-patches/resources-patch.yaml
  - replica-patch.yaml
```

---

## Configuration Details

### Environment Variables Available

From `tazama-config` ConfigMap:
- `CONFIGURATION_DB_URL` - Configuration database connection
- `TRANSACTION_HISTORY_DB_URL` - Transaction history database
- `PSEUDONYMS_DB_URL` - Pseudonyms database
- `EVALUATIONS_DB_URL` - Evaluations database (future)
- `NATS_SERVER_URL` - NATS messaging
- `ELASTIC_HOST` - Elasticsearch (if enabled)
- Plus many more (see `tazama-config.yaml`)

From `tazama-secrets` Secret:
- `POSTGRES_PASSWORD` - Master password
- `CONFIGURATION_DB_PASSWORD` - Config DB password
- `TRANSACTION_HISTORY_DB_PASSWORD` - Transaction DB password
- `PSEUDONYMS_DB_PASSWORD` - Pseudonyms DB password
- `NATS_PASSWORD` - NATS password (if auth enabled)

---

## Performance Optimization

### Connection Pooling

Set in ConfigMap:
```yaml
DB_POOL_SIZE: "100"           # Based on postgres-poc recommendations
DB_IDLE_TIMEOUT: "10000"      # 10 seconds
DB_CONNECTION_TIMEOUT: "2000" # 2 seconds
```

### Indexes

Already created in `init-databases.sql`:
- Transaction ID, timestamp, type
- Creditor/debtor IDs
- Amount ranges
- GIN indexes for JSONB searches

### Monitoring

PostgreSQL exporter is enabled in the Helm chart:

```bash
# Check metrics
kubectl port-forward -n infrastructure \
  svc/postgres-postgresql-metrics 9187:9187

# Grafana dashboards
kubectl port-forward -n infrastructure \
  svc/monitoring-grafana 3000:80

# Login: admin / admin (change in production!)
# Import PostgreSQL dashboard
```

---

## Migration from ArangoDB

### If You Have Existing ArangoDB Data

1. **Export from ArangoDB:**
```bash
# Export each collection as JSONL
arangodump --server.endpoint tcp://arango:8529 \
  --output-directory ./arango-backup
```

2. **Convert to PostgreSQL:**
```bash
# You'll need a custom migration script
# Contact Tazama team for migration tools
```

3. **Import to PostgreSQL:**
```bash
# Use COPY or INSERT statements
# Example for transactions:
kubectl exec -i postgres-postgresql-0 -n infrastructure -- \
  psql -U tazama -d transactionHistory \
  -c "COPY transactions(transaction_data) FROM STDIN WITH (FORMAT csv);" \
  < transactions.csv
```

### Code Changes (Already in v3.0.0 Images)

Application code changes were minimal:
- Replaced `arangojs` with `pg` (node-postgres)
- Changed query syntax from AQL to SQL
- Updated connection strings
- Mapped result sets to existing interfaces

**No code changes needed in your deployment!**

---

## Backup and Restore

### Backup All Databases

```bash
# Full backup
kubectl exec postgres-postgresql-0 -n infrastructure -- \
  pg_dumpall -U postgres > tazama-backup-$(date +%Y%m%d).sql

# Single database backup
kubectl exec postgres-postgresql-0 -n infrastructure -- \
  pg_dump -U tazama transactionHistory > transactions-backup.sql
```

### Restore

```bash
# Restore all
kubectl exec -i postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres < tazama-backup.sql

# Restore single database
kubectl exec -i postgres-postgresql-0 -n infrastructure -- \
  psql -U tazama transactionHistory < transactions-backup.sql
```

### Automated Backups

Consider using:
- **Velero** for cluster-level backups
- **pg_dump** cron jobs
- **WAL archiving** to S3/GCS

---

## Troubleshooting

### Can't Connect to PostgreSQL

```bash
# Check if PostgreSQL is running
kubectl get pods -n infrastructure -l app.kubernetes.io/name=postgresql

# Check logs
kubectl logs -n infrastructure postgres-postgresql-0

# Test connection
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -c "SELECT version();"
```

### Databases Not Created

```bash
# List databases
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -c "\l"

# If missing, run init script again
kubectl cp k8s/postgres/init-databases.sql \
  infrastructure/postgres-postgresql-0:/tmp/init.sql
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -f /tmp/init.sql
```

### Services Can't Connect

```bash
# Check secrets exist
kubectl get secret tazama-secrets -n staging

# Check config exists
kubectl get configmap tazama-config -n staging

# Verify deployment has envFrom
kubectl get deployment rule-001 -n staging -o yaml | grep -A5 envFrom

# Check actual environment in pod
kubectl exec -it <pod-name> -n staging -- env | grep -E '(POSTGRES|DB_)'
```

### Performance Issues

```bash
# Check connection count
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check slow queries
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -c "SELECT query, calls, total_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# Enable pg_stat_statements if not enabled
kubectl exec -it postgres-postgresql-0 -n infrastructure -- \
  psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

---

## Advanced: TimescaleDB or Citus

For production scale (from postgres-poc notes):

### TimescaleDB (Time-Series Optimization)

```sql
-- Create TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Convert transactions table to hypertable
SELECT create_hypertable('transactions', 'created_at');

-- Automatic partitioning by time!
```

### Citus (Horizontal Scaling)

For very high transaction volumes:
- Distribute transactionHistory across multiple nodes
- Keep configuration/pseudonyms on single instance

See [Citus Documentation](https://docs.citusdata.com/)

---

## References

- [PostgreSQL POC Repository](https://github.com/tazama-lf/postgres-poc)
- [PostgreSQL POC Notes](https://github.com/tazama-lf/postgres-poc/blob/mono-repo/docs/notes.md)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [JSONB Performance](https://www.postgresql.org/docs/current/datatype-json.html)

---

## Summary Checklist

- [ ] PostgreSQL deployed via `make infrastructure`
- [ ] Databases initialized with `init-databases.sql`
- [ ] ConfigMap created (`tazama-config.yaml`)
- [ ] Sealed secrets created and applied
- [ ] Services updated to use ConfigMap and Secrets
- [ ] Connection tested from a pod
- [ ] Backup strategy defined
- [ ] Monitoring dashboards configured

---

**PostgreSQL setup complete!** Your Tazama deployment now uses PostgreSQL v3.0.0. 🚀
