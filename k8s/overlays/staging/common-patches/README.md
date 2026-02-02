# Common Patches for Staging Environment

This directory contains reusable Kustomize patches that can be applied across multiple services in the staging environment.

## Available Patches

### 1. `resources-patch.yaml`
Adds resource requests and limits to deployments.

**Current values:**
- CPU Request: 100m
- CPU Limit: 500m
- Memory Request: 256Mi
- Memory Limit: 512Mi

**To apply to a service:**
Add to the service's `kustomization.yaml`:
```yaml
patchesStrategicMerge:
  - ../../common-patches/resources-patch.yaml
  - replica-patch.yaml
```

**Note:** These are baseline values. Adjust based on actual service requirements after load testing.

## Usage Example

For `rule-001`, the `k8s/overlays/staging/rule-001/kustomization.yaml` would include:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/rule-001
namespace: staging
commonLabels:
  env: staging
patchesStrategicMerge:
  - ../../common-patches/resources-patch.yaml  # Apply common resource limits
  - replica-patch.yaml                         # Service-specific replica count
```

## Creating New Patches

To create environment-wide patches (for all services):
1. Add the patch YAML file to this directory
2. Reference it in each service's kustomization.yaml
3. Document it in this README
