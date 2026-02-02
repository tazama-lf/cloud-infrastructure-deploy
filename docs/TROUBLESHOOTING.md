# Troubleshooting Guide

Common issues and solutions for Tazama deployment.

## Table of Contents

- [Prerequisites Issues](#prerequisites-issues)
- [Cluster Creation Issues](#cluster-creation-issues)
- [ArgoCD Issues](#argocd-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [Application Issues](#application-issues)
- [Sealed Secrets Issues](#sealed-secrets-issues)
- [Networking Issues](#networking-issues)

---

## Prerequisites Issues

### kubectl not found

**Error:**
```
kubectl: command not found
```

**Solution:**
```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### helm not found

**Error:**
```
helm: command not found
```

**Solution:**
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### AWS CLI not configured

**Error:**
```
Unable to locate credentials
```

**Solution:**
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, and region
```

---

## Cluster Creation Issues

### Terraform state locked

**Error:**
```
Error: Error locking state: Error acquiring the state lock
```

**Solution:**
```bash
cd terraform-scripts/eks-terraform

# Force unlock (use with caution!)
terraform force-unlock <lock-id>

# Or delete the lock in DynamoDB
aws dynamodb delete-item \
  --table-name terraform-lock \
  --key '{"LockID":{"S":"<lock-id>"}}'
```

### Insufficient permissions

**Error:**
```
Error: error creating EKS Cluster: AccessDeniedException
```

**Solution:**
- Verify your IAM user has EKS full access
- Check if you need additional VPC/EC2 permissions
- Try with an admin role temporarily to identify missing permissions

### Cluster already exists

**Error:**
```
Error: EKS Cluster (tazama-eks) already exists
```

**Solution:**
```bash
# Option 1: Use existing cluster
make configure-kubectl

# Option 2: Destroy and recreate
cd terraform-scripts/eks-terraform
terraform destroy -auto-approve
terraform apply -auto-approve
```

---

## ArgoCD Issues

### ArgoCD pods not starting

**Error:**
```
argocd-server pod in CrashLoopBackOff
```

**Solution:**
```bash
# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Common fix: Restart deployment
kubectl rollout restart deployment argocd-server -n argocd

# If persistent, reinstall
kubectl delete namespace argocd
make install-argocd
```

### Can't access ArgoCD UI

**Error:**
```
Connection refused on localhost:8080
```

**Solution:**
```bash
# Check if port-forward is running
lsof -i :8080

# If not, start it
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check argocd-server is running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
```

### Forgot ArgoCD password

**Solution:**
```bash
# Get the initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Or reset it
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'$(htpasswd -nbBC 10 "" newpassword | tr -d ':\n' | sed 's/$2y/$2a/')'"}}'
```

### Applications stuck in "Unknown" state

**Solution:**
```bash
# Refresh all applications
kubectl get applications -n argocd -o name | xargs -I {} kubectl patch {} -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'

# Or using argocd CLI
argocd app list -o name | xargs -I {} argocd app get {} --refresh
```

### Repository URL incorrect

**Error:**
```
ComparisonError: error resolving git repository
```

**Solution:**
```bash
# Check if repository is accessible
git ls-remote https://github.com/tazama-lf/cloud-infrastructure-deploy

# Update repository URL in applications
kubectl edit application <app-name> -n argocd

# Or update all at once
find apps -name "*.yaml" -exec sed -i '' 's|old-url|new-url|g' {} \;
git commit -am "fix: update repository URLs"
git push
```

---

## Infrastructure Issues

### PostgreSQL pod not starting

**Error:**
```
pod "postgres-postgresql-0" 0/1 CrashLoopBackOff
```

**Solutions:**

1. **Check logs:**
```bash
kubectl logs -n infrastructure postgres-postgresql-0
```

2. **Insufficient resources:**
```bash
# Check node resources
kubectl top nodes
kubectl describe node <node-name>

# Scale up cluster if needed
```

3. **PVC issues:**
```bash
# Check persistent volume claims
kubectl get pvc -n infrastructure

# If pending, check storage class
kubectl get storageclass

# Delete and recreate if needed
kubectl delete pvc data-postgres-postgresql-0 -n infrastructure
```

### NATS pod not starting

**Error:**
```
pod "nats-0" 0/1 Init:Error
```

**Solution:**
```bash
# Check logs
kubectl logs -n infrastructure nats-0

# Common issue: JetStream storage
kubectl describe pod nats-0 -n infrastructure

# If storage issue, check PVC
kubectl get pvc -n infrastructure
```

### Monitoring stack too resource-intensive

**Error:**
```
prometheus pod OOMKilled
```

**Solution:**
```bash
# Edit the application to reduce resources
kubectl edit application monitoring -n argocd

# Update Helm values:
# prometheus:
#   prometheusSpec:
#     resources:
#       requests:
#         memory: "1Gi"
#       limits:
#         memory: "2Gi"
```

---

## Application Issues

### Pods in ImagePullBackOff

**Error:**
```
Failed to pull image "tazamaorg/rule-001:3.0.0": rpc error: code = Unknown desc = Error response from daemon: pull access denied
```

**Solutions:**

1. **Images are private - Create ImagePullSecret:**
```bash
kubectl create secret docker-registry tazama-dockerhub \
  --docker-username=<username> \
  --docker-password=<token> \
  --docker-email=<email> \
  -n staging

# Then add to deployment (see README Step 4.5)
```

2. **Image doesn't exist:**
```bash
# Verify image exists
docker pull tazamaorg/rule-001:3.0.0

# Check if version is correct
kubectl get deployment rule-001 -n staging -o yaml | grep image:
```

3. **Rate limited by Docker Hub:**
```bash
# Use Docker Hub credentials (even for public images)
# This increases rate limit from 100 to 200 pulls per 6 hours
```

### Pods in CrashLoopBackOff

**Error:**
```
Back-off restarting failed container
```

**Solutions:**

1. **Check logs:**
```bash
kubectl logs -n staging <pod-name>
kubectl logs -n staging <pod-name> --previous  # Last crashed instance
```

2. **Common causes:**
   - Missing environment variables (database connection, NATS URL)
   - Can't connect to database
   - Can't connect to NATS
   - Application error

3. **Check environment:**
```bash
kubectl exec -it -n staging <pod-name> -- env | grep -E '(POSTGRES|NATS)'
```

4. **Test connectivity:**
```bash
# Test PostgreSQL
kubectl exec -it -n staging <pod-name> -- \
  nc -zv postgres-postgresql.infrastructure.svc.cluster.local 5432

# Test NATS
kubectl exec -it -n staging <pod-name> -- \
  nc -zv nats.infrastructure.svc.cluster.local 4222
```

### Services can't connect to PostgreSQL

**Error:**
```
Error: connect ECONNREFUSED postgres-postgresql.infrastructure.svc.cluster.local:5432
```

**Solutions:**

1. **Verify PostgreSQL is running:**
```bash
kubectl get pods -n infrastructure -l app.kubernetes.io/name=postgresql
```

2. **Check service DNS:**
```bash
kubectl get svc -n infrastructure postgres-postgresql

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup postgres-postgresql.infrastructure.svc.cluster.local
```

3. **Verify credentials:**
```bash
# Get password
kubectl get secret postgres-postgresql -n infrastructure \
  -o jsonpath="{.data.postgres-password}" | base64 -d

# Test connection
kubectl run -it --rm psql --image=postgres:16 --restart=Never -- \
  psql -h postgres-postgresql.infrastructure.svc.cluster.local \
  -U postgres
```

4. **Add ConfigMap with connection info:**
```bash
kubectl apply -f k8s/overlays/staging/common-patches/sample-configmap.yaml
```

---

## Sealed Secrets Issues

### Controller not running

**Error:**
```
error: unable to recognize "sealed-secret.yaml": no matches for kind "SealedSecret"
```

**Solution:**
```bash
# Install controller
kubectl apply -f k8s/sealed-secrets/controller-application.yaml

# Verify it's running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Can't seal secrets - certificate error

**Error:**
```
error: cannot fetch certificate: unable to connect
```

**Solution:**
```bash
# Check if controller is accessible
kubectl get svc -n kube-system sealed-secrets-controller

# Fetch certificate manually
kubeseal --fetch-cert \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller \
  > pub-cert.pem

# Use certificate for sealing
kubeseal --cert=pub-cert.pem < secret.yaml > sealed-secret.yaml
```

### Sealed secret not creating regular secret

**Solution:**
```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify SealedSecret was created
kubectl get sealedsecrets -n staging

# Check events
kubectl describe sealedsecret <name> -n staging
```

---

## Networking Issues

### LoadBalancer stuck in Pending

**Error:**
```
service "ingress-nginx-controller" External-IP <pending>
```

**Solution:**
```bash
# Check if AWS Load Balancer Controller is installed
kubectl get pods -n kube-system | grep aws-load-balancer

# Check events
kubectl describe svc ingress-nginx-controller -n infrastructure

# AWS specific: Check Security Groups and Subnets
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/tazama-eks,Values=owned"
```

### Pods can't reach external services

**Solution:**
```bash
# Check NAT Gateway
aws ec2 describe-nat-gateways

# Check route tables
kubectl get nodes -o wide
# Verify nodes are in private subnets with NAT gateway route

# Test external connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -I https://www.google.com
```

---

## General Debugging Commands

### Get all resources in a namespace

```bash
kubectl get all -n staging
kubectl get all -n infrastructure
```

### Describe a problematic resource

```bash
kubectl describe pod <pod-name> -n staging
kubectl describe deployment <deployment-name> -n staging
```

### Get events

```bash
# All events in namespace
kubectl get events -n staging --sort-by='.lastTimestamp'

# Watch events
kubectl get events -n staging --watch
```

### Execute commands in a pod

```bash
kubectl exec -it <pod-name> -n staging -- /bin/sh
kubectl exec -it <pod-name> -n staging -- env
```

### Port forward for debugging

```bash
kubectl port-forward -n staging <pod-name> 8080:8080
```

### Check resource usage

```bash
kubectl top nodes
kubectl top pods -n staging
kubectl top pods -n infrastructure
```

---

## Getting Help

If you're still stuck:

1. Check [GitHub Issues](https://github.com/tazama-lf/cloud-infrastructure-deploy/issues)
2. Review [Deployment Guide](DEPLOYMENT.md)
3. Check [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
4. Review [Kubernetes Documentation](https://kubernetes.io/docs/)
5. Open a new issue with:
   - Error message
   - Output of relevant `kubectl describe` or `kubectl logs`
   - Steps to reproduce
