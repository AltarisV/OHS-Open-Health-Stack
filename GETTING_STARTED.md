# Getting Started: Open Health Stack

## 5-Minute Quick Start

### Prerequisites
- Kubernetes cluster 1.24+
- Helm 3.12+
- kubectl configured
- Storage class available
- Ingress controller installed (Nginx, Traefik)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/ohs-open-health-stack.git
cd ohs-open-health-stack

# 2. Create namespace
kubectl create namespace ohs
kubectl config set-context --current --namespace=ohs

# 3. Create secrets (replace with your passwords)
kubectl create secret generic ohs-credentials \
  --from-literal=ehrbase-user-password=MySecurePassword123 \
  --from-literal=ehrbase-db-password=MyDbPassword456 \
  --from-literal=openfhir-mongo-uri=mongodb://openfhir:MyMongoPass789@mongodb-cluster:27017/openfhir \
  --from-literal=eos-db-password=MyEosPassword000 \
  -n ohs

# 4. Install OHS Helm chart
helm install ohs . -f values.yaml -n ohs

# 5. Wait for pods (5-15 minutes)
kubectl get pods -n ohs -w
```

### Access the Platform

```bash
# Port-forward to EHRbase (in a new terminal)
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs

# Test EHRbase
curl -s http://localhost:8080/health | jq .

# Port-forward to openFHIR
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs

# Query FHIR Patient resource
curl -s 'http://localhost:8081/fhir/Patient' | jq .
```

---

## Common Tasks

### Check Deployment Status

```bash
# All pods
kubectl get pods -n ohs

# Pod details
kubectl describe pod ohs-ehrbase-0 -n ohs

# Pod logs
kubectl logs ohs-ehrbase-0 -n ohs
kubectl logs -f ohs-ehrbase-0 -n ohs  # Follow logs
```

### Access Databases

```bash
# PostgreSQL shell
kubectl exec -it postgres-cluster-0 -n ohs -- psql -U ehrbase -d ehrbase

# List databases
\l

# List tables
\dt ehrbase.*

# Exit
\q
```

```bash
# MongoDB shell
kubectl exec -it mongodb-cluster-0 -n ohs -- mongosh

# Switch database
use openfhir

# List collections
show collections

# Query
db.Patient.findOne()

# Exit
exit
```

### View Helm Values

```bash
# Current values
helm get values ohs -n ohs

# Values for specific chart
helm get values ohs -n ohs | grep ehrbase -A 10
```

### Update Configuration

```bash
# Edit custom values file
vim values-prod.yaml

# Apply changes
helm upgrade ohs . -f values-prod.yaml -n ohs

# Monitor rollout
kubectl rollout status deployment/ohs-ehrbase -n ohs
```

### Scaling Components

```bash
# Scale EHRbase replicas
kubectl scale deployment ohs-ehrbase --replicas=3 -n ohs

# Scale PostgreSQL (CloudNativePG)
kubectl patch cloudnativepgcluster postgres-cluster -n ohs \
  -p '{"spec":{"instances":5}}'
```

---

## Troubleshooting

### Pods in CrashLoopBackOff

```bash
# Check logs
kubectl logs ohs-ehrbase-0 -n ohs --previous

# Check events
kubectl describe pod ohs-ehrbase-0 -n ohs

# Common causes:
# - Database connection refused: Wait for database to initialize
# - Invalid credentials: Verify ohs-credentials secret
# - Memory pressure: Increase node capacity or request limits
```

### Database Not Ready

CloudNativePG and MongoDB operators take 5-15 minutes to initialize:

```bash
# Check PostgreSQL cluster status
kubectl get cloudnativepgclusters -n ohs

# Check MongoDB replica set status
kubectl get mongodbcommunity -n ohs

# View operator logs
kubectl logs -l app=postgres-operator -n ohs
kubectl logs -l app=mongodb-operator -n ohs
```

### PVC Not Binding

```bash
# Check available storage classes
kubectl get storageclass

# Check PVC status
kubectl describe pvc -n ohs

# If no default storage class, create one or specify in values.yaml
```

### Ingress Not Working

```bash
# Check Ingress status
kubectl describe ingress ohs-ingress -n ohs

# Verify Ingress controller running
kubectl get pods -n ingress-nginx
kubectl get pods -n traefik

# Test ingress IP
kubectl get ingress -n ohs
# Then curl: curl http://<INGRESS_IP>/ehrbase/health
```

---

## Building Custom Images

### openEHRTool-v2

openEHRTool-v2 has no published Docker image. Build locally:

```bash
cd packaging/openEHRTool-v2

# Build
docker build -t myregistry/opehrtool-v2:0.1.0 .

# Push
docker push myregistry/opehrtool-v2:0.1.0

# Enable in values.yaml
opehrtool-v2:
  enabled: true
  image:
    repository: myregistry/opehrtool-v2
    tag: 0.1.0

# Deploy
helm upgrade ohs . -f values.yaml -n ohs
```

---

## Next Steps

1. **Explore APIs**:
   - EHRbase: http://localhost:8080/swagger-ui/
   - openFHIR: http://localhost:8081/swagger-ui/

2. **Load test data**:
   - See `DEPLOYMENT.md` for example patient creation

3. **Configure production**:
   - Set strong passwords in `ohs-credentials` secret
   - Configure TLS/HTTPS via cert-manager
   - Set up persistent backup strategy

4. **Monitor deployment**:
   - Install Prometheus/Grafana (optional)
   - Configure log aggregation (ELK, Loki)

5. **Implement additional components**:
   - Build and deploy openEHRTool-v2
   - Integrate BETTER Platform data mirroring (Phase N)

---

## Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Full deployment guide with prerequisites
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture and data flows
- **[VALUES.md](VALUES.md)** - Complete configuration reference
- **[SECRETS.md](SECRETS.md)** - Secret management best practices

---

## Support

- **Issues**: https://github.com/yourusername/ohs-open-health-stack/issues
- **Discussions**: https://github.com/yourusername/ohs-open-health-stack/discussions
- **EHRbase Docs**: https://docs.ehrbase.org/
- **openFHIR GitHub**: https://github.com/openfhir/openfhir
- **Kubernetes Docs**: https://kubernetes.io/docs/

