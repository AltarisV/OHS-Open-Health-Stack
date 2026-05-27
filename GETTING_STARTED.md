# Getting Started: Open Health Stack

## Quick Start

```bash
# 1. Install operators (one-time cluster setup)
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cnpg-system cnpg/cloudnative-pg -n cnpg-system --create-namespace

helm repo add mongodb https://mongodb.github.io/helm-charts
helm install mongodb-operator mongodb/community-operator -n mongodb-operator --create-namespace \
  --set operator.watchNamespace=ohs

# 2. Create namespace and credentials secret
kubectl create namespace ohs
kubectl label namespace ohs name=ohs
kubectl create secret generic ohs-credentials -n ohs \
  --from-literal=ehrbase-user-password=YOUR_PASSWORD \
  --from-literal=ehrbase-db-password=YOUR_DB_PASSWORD \
  --from-literal=openfhir-mongo-uri='mongodb://openfhir:MONGO_PASS@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir' \
  --from-literal=eos-db-password=YOUR_EOS_PASSWORD \
  --from-literal=redis-password=YOUR_REDIS_PASSWORD

# 3. Deploy
helm install ohs . -f values.yaml -n ohs

# 4. Watch pods (databases take 5-15 min)
kubectl get pods -n ohs -w
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full prerequisites and production notes.

---

## Access the Services

Run each in a separate terminal:

```bash
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs
kubectl port-forward svc/ohs-eos 8082:8080 -n ohs
```

| Service | URL | Notes |
|---------|-----|-------|
| EHRbase | http://localhost:8080/ehrbase/rest/openehr/v1/ | Basic auth: ehrbase_user / your password |
| EHRbase Swagger | http://localhost:8080/swagger-ui/ | |
| openFHIR | http://localhost:8081/fhir/metadata | FHIR R4 |
| Eos | http://localhost:8082/actuator/health | Spring Boot actuator |

See [VERIFICATION.md](VERIFICATION.md) for end-to-end testing steps.

---

## Common Operations

```bash
# Check pod status and logs
kubectl get pods -n ohs
kubectl logs -l app=ehrbase -n ohs --tail=50
kubectl describe pod <pod-name> -n ohs

# Apply config changes
helm upgrade ohs . -f values.yaml -n ohs
kubectl rollout status deployment/ohs-ehrbase -n ohs

# PostgreSQL shell (EHRbase DB)
kubectl exec -it postgres-cluster-1 -n ohs -- psql -U ehrbase -d ehrbase

# MongoDB shell
kubectl exec -it mongodb-cluster-0 -n ohs -- mongosh -u root -p YOUR_ROOT_PASS
```

---

## Building openEHRTool-v2 (Optional)

No published Docker image exists upstream. Build it manually:

```bash
git clone https://github.com/crs4/openEHRTool-v2.git packaging/openEHRTool-v2/src
# Write multi-stage Dockerfile: Node 22 (Vue build) + Python 3.11-slim (FastAPI runtime)
docker build -t your-registry/opehrtool-v2:0.1.0 packaging/openEHRTool-v2/
docker push your-registry/opehrtool-v2:0.1.0
```

Then set `opehrtool-v2.enabled: true` and `image.repository/tag` in your values file.

---

## Documentation

| File | Contents |
|------|----------|
| [DEPLOYMENT.md](DEPLOYMENT.md) | Full deployment guide + production notes |
| [VERIFICATION.md](VERIFICATION.md) | Health checks + end-to-end testing |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Component overview and data flows |
| [SECRETS.md](SECRETS.md) | Secret management options |
| [VALUES.md](VALUES.md) | Complete configuration reference |
| [NEXT_STEPS.md](NEXT_STEPS.md) | Roadmap and future phases |
