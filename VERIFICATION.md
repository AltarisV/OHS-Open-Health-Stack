# Verification Guide: Open Health Stack

This guide provides step-by-step verification procedures to ensure OHS is deployed correctly.

## Pre-Deployment Verification

### 1. Helm Chart Syntax

Validate Helm chart structure before deployment:

```bash
# Lint the chart (checks YAML syntax, best practices)
helm lint . -f values.yaml

# Expected output: "1 chart(s) linted, 0 error(s)"
```

### 2. Template Rendering

Verify templates render correctly:

```bash
# Dry-run: Generate manifests without deploying
helm template ohs . -f values.yaml --debug

# Check specific chart
helm template ohs . -f values.yaml --show-only=charts/ehrbase/templates/deployment.yaml

# Validate manifests (requires kubeval)
helm template ohs . -f values.yaml | kubeval --strict
```

### 3. Values Validation

Check for placeholders that must be customized:

```bash
# Search for placeholder values
grep -r "example.org\|CHANGE_ME\|PIN_VERSION\|YOUR_" . --include="*.yaml"

# Expected: Only in values.yaml (not in templates after rendering)
```

---

## Deployment Verification

### 1. Helm Installation

```bash
# Install with dry-run (no actual deployment)
helm install ohs . -f values.yaml -n ohs --dry-run

# Install for real (requires confirmation)
helm install ohs . -f values.yaml -n ohs

# Check release status
helm status ohs -n ohs
helm list -n ohs

# Check release history
helm history ohs -n ohs
```

### 2. Pod Status

```bash
# Watch pods coming up
kubectl get pods -n ohs -w

# Check pod readiness (wait 5-15 minutes for databases)
kubectl get pods -n ohs -o wide

# Expected: All pods in Running state with Ready 1/1
```

### 3. Pod Initialization

```bash
# Check logs for each pod
for pod in $(kubectl get pods -n ohs -o name); do
  echo "=== Logs for $pod ==="
  kubectl logs $pod -n ohs --tail=20
done

# Expected: No CrashLoopBackOff, Error, or warning messages
```

### 4. Database Readiness

```bash
# Check CloudNativePG cluster
kubectl get cloudnativepgclusters -n ohs
kubectl describe cloudnativepgcluster postgres-cluster -n ohs

# Expected: Status.Phase = "Cluster in healthy state"

# Check MongoDB cluster
kubectl get mongodbcommunity -n ohs
kubectl describe mongodbcommunity mongodb-cluster -n ohs

# Expected: Status.Phase = "Running"
```

### 5. Service Availability

```bash
# List all services
kubectl get svc -n ohs

# Check service endpoints
kubectl get endpoints -n ohs

# Test service connectivity (from within cluster)
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -n ohs -- \
  wget -q -O- http://ohs-ehrbase:8080/health
```

---

## Post-Deployment Verification

### 1. Application Health Checks

```bash
# Forward ports for manual testing
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs &
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs &

# Test EHRbase health endpoint
curl -s http://localhost:8080/health | jq .

# Expected response:
# {
#   "status": "UP",
#   "components": {
#     "db": { "status": "UP" },
#     ...
#   }
# }

# Test EHRbase API
curl -s -u ehrbase:changeme http://localhost:8080/swagger-ui/ | head -20

# Test openFHIR
curl -s http://localhost:8081/fhir/Patient | jq '.type'

# Expected: "Bundle"
```

### 2. Database Verification

```bash
# PostgreSQL: Query ehrbase database
kubectl exec -it postgres-cluster-0 -n ohs -- \
  psql -U ehrbase -d ehrbase -c "SELECT version();"

# MongoDB: Query openfhir database
kubectl exec -it mongodb-cluster-0 -n ohs -- \
  mongosh --eval "db.adminCommand('ping')"

# Expected: pong: 1
```

### 3. Data Persistence

```bash
# Create test data
curl -s -u ehrbase:changeme -X POST http://localhost:8080/rest/v1/ehr \
  -H "Content-Type: application/json" \
  -d '{
    "ehr_status": {
      "archetype_node_id": "at0001",
      "_type": "EHR_STATUS"
    }
  }'

# Delete pod to trigger restart
kubectl delete pod ohs-ehrbase-0 -n ohs

# Verify data persists after pod restart
# (check logs for database recovery)
```

### 4. Configuration Verification

```bash
# Check mounted ConfigMaps
kubectl get configmap -n ohs

# Verify environment variables
kubectl exec ohs-ehrbase-0 -n ohs -- env | grep -i "DB_\|SPRING_"

# Expected: Database connection strings, security settings
```

### 5. Networking Verification

```bash
# Check DNS resolution (from pod)
kubectl exec -it ohs-ehrbase-0 -n ohs -- \
  nslookup ohs-openfhir.ohs.svc.cluster.local

# Check Ingress
kubectl get ingress -n ohs
kubectl describe ingress ohs-ingress -n ohs

# Expected: Ingress IP assigned, rules configured

# Test Ingress routing
INGRESS_IP=$(kubectl get svc -n ingress-nginx | grep LoadBalancer | awk '{print $4}')
curl -s -H "Host: ohs.example.org" http://$INGRESS_IP/ehrbase/health
```

### 6. RBAC Verification

```bash
# Check ServiceAccount
kubectl get sa -n ohs

# Check ClusterRole
kubectl get clusterrole -l app=ohs

# Verify RBAC permissions
kubectl auth can-i get pods --as=system:serviceaccount:ohs:ohs -n ohs

# Expected: yes (for authorized actions)
```

### 7. NetworkPolicy Verification

```bash
# Verify NetworkPolicy is installed
kubectl get networkpolicy -n ohs

# Test network isolation (should be blocked)
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -n default -- \
  wget --timeout=2 -q -O- http://ohs-ehrbase.ohs.svc.cluster.local:8080/health

# Expected: Connection timeout (cross-namespace denied)

# Test from same namespace (should work)
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -n ohs -- \
  wget -q -O- http://ohs-ehrbase:8080/health

# Expected: Successfully downloaded page
```

---

## Monitoring & Observability Verification

### 1. Prometheus Integration

```bash
# If monitoring enabled, check ServiceMonitor
kubectl get servicemonitor -n ohs

# Verify metrics endpoints are scraped
kubectl logs -l app=prometheus -n monitoring | grep -i "ohs"
```

### 2. Pod Disruption Budget

```bash
# Verify PDB is created
kubectl get poddisruptionbudget -n ohs

# Check allowed disruptions
kubectl get pdb -n ohs -o wide

# Expected: minAvailable: 1 for each component
```

### 3. Resource Usage

```bash
# Check node resource availability
kubectl top nodes

# Check pod resource usage
kubectl top pods -n ohs

# Expected: All pods have memory/CPU assigned within requests
```

---

## Upgrade Verification

### 1. Before Upgrade

```bash
# Verify current version
helm list -n ohs

# Check what will change
helm diff upgrade ohs . -f values.yaml -n ohs

# Expected: Only config/version changes, no data loss
```

### 2. During Upgrade

```bash
# Upgrade chart
helm upgrade ohs . -f values.yaml -n ohs

# Monitor rollout
kubectl rollout status deployment/ohs-ehrbase -n ohs
kubectl rollout status statefulset/postgres-cluster -n ohs

# Watch for pod restarts
kubectl get pods -n ohs -w
```

### 3. After Upgrade

```bash
# Verify all pods healthy
kubectl get pods -n ohs

# Re-run application health checks
curl -s http://localhost:8080/health | jq .

# Verify data intact
kubectl exec -it postgres-cluster-0 -n ohs -- \
  psql -U ehrbase -d ehrbase -c "SELECT COUNT(*) FROM ehr.ehr;"
```

---

## Uninstall Verification

```bash
# Uninstall Helm release
helm uninstall ohs -n ohs

# Verify pods are deleted
kubectl get pods -n ohs

# Expected: No resources remaining

# Verify PVCs are cleaned up (if deletePolicy: Delete)
kubectl get pvc -n ohs

# Verify secrets are deleted
kubectl get secrets -n ohs

# Clean up namespace if needed
kubectl delete namespace ohs
```

---

## Troubleshooting Verification

### Pod Failed to Start

```bash
# 1. Check pod events
kubectl describe pod ohs-ehrbase-0 -n ohs

# 2. Check logs
kubectl logs ohs-ehrbase-0 -n ohs --previous

# 3. Check resource constraints
kubectl top pod ohs-ehrbase-0 -n ohs

# 4. Check node status
kubectl describe node <node-name>
```

### Database Connection Failed

```bash
# 1. Verify database pod is running
kubectl get pods -l app=postgres-cluster -n ohs

# 2. Test database connectivity
kubectl exec -it postgres-cluster-0 -n ohs -- \
  psql -U ehrbase -d ehrbase -c "SELECT 1"

# 3. Check database configuration secret
kubectl get secret postgres-secret -n ohs -o jsonpath='{.data}'

# 4. Verify network connectivity
kubectl exec -it ohs-ehrbase-0 -n ohs -- \
  nc -zv postgres-cluster 5432
```

### Ingress Not Routing

```bash
# 1. Check ingress status
kubectl get ingress ohs-ingress -n ohs -o yaml

# 2. Check ingress controller logs
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx

# 3. Test DNS resolution
nslookup ohs.example.org

# 4. Test HTTP connectivity
curl -v -H "Host: ohs.example.org" http://<INGRESS_IP>/ehrbase/health
```

---

## Automated Testing

Use these commands in CI/CD pipelines:

```bash
#!/bin/bash
set -e

# Lint
helm lint . -f values.yaml

# Template validation
helm template ohs . -f values.yaml | kubeval --strict

# Install (dry-run)
helm install ohs . -f values.yaml -n ohs --dry-run

# Check for secrets in values
! grep -r "example.org\|PIN_VERSION" . --include="*.yaml" || exit 1

echo "All verifications passed!"
```

---

## Performance Benchmarks

Expected metrics for healthy deployment:

| Component | Metric | Expected |
|-----------|--------|----------|
| EHRbase | Startup time | < 60 seconds |
| EHRbase | Memory usage | 512 MB - 2 GB |
| openFHIR | Response time (GET /Patient) | < 500 ms |
| PostgreSQL | Query latency | < 50 ms |
| MongoDB | Document retrieval | < 100 ms |
| Ingress | Request latency | < 100 ms |

---

## Success Criteria

- All deployment verification steps pass
- All pods in Running state with Ready 1/1
- Databases initialized and accepting connections
- Health endpoints respond with status: UP
- Sample data created and retrieved successfully
- Network policies enforced correctly
- RBAC permissions validate correctly
- Helm upgrade/downgrade works without data loss
- Monitoring (if enabled) shows expected metrics
- No errors in pod logs

---

## Next Steps

1. **Load Production Data**: Use CSV-to-openEHR importer
2. **Configure Backups**: Set backup policies for databases
3. **Set Up Monitoring**: Install Prometheus/Grafana (optional)
4. **Implement Custom Workflows**: Use openEHRTool-v2 for data entry
5. **Scale**: Increase replicas based on load tests

---

## References

- **Helm Testing**: https://helm.sh/docs/helm/helm_test/
- **Kubernetes Debugging**: https://kubernetes.io/docs/tasks/debug-application-cluster/debug-pod-replication-controller/
- **Performance Testing**: https://github.com/kubernetes/perf-tests
- **EHRbase Health Checks**: https://docs.ehrbase.org/

