# Getting Started: Open Health Stack

## Choose Your Cluster Mode

- Standard Kubernetes cluster: recommended default for home servers and shared clusters.
- Optional Minikube local profile: useful for laptop-only/local testing.

If you use Minikube, start it before the quick start flow:

```bash
minikube start --driver=docker
```

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
cp .env.example .env  # fill in all values, then:
bash create-secret.sh

# 3. Deploy
helm install ohs . -f values.yaml -n ohs

# 4. Watch pods (databases take 5-15 min)
kubectl get pods -n ohs -w
```

For Minikube local mode, use the local override file and keep MongoDB user password aligned with your .env value:

```bash
set -a; source .env; set +a
helm upgrade --install ohs . -f values.yaml -f values-minikube.yaml -n ohs \
  --set-string mongodb.openfhir.userPassword="$OPENFHIR_MONGO_PASSWORD"
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full prerequisites and production notes.

---

## Access the Services

Run each in a separate terminal:

```bash
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs
kubectl port-forward svc/ohs-eos 8082:8081 -n ohs
```

If Cohort Explorer is enabled, add:

```bash
kubectl port-forward svc/ohs-keycloak 8083:8080 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-backend 8084:8090 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-frontend 8085:80 -n ohs
```

| Service | URL | Notes |
|---------|-----|-------|
| EHRbase | http://localhost:8080/ehrbase/rest/openehr/v1/ | Basic auth: ehrbase_user / your password |
| EHRbase Swagger | http://localhost:8080/swagger-ui/ | |
| openFHIR | http://localhost:8081/fhir/metadata | FHIR R4 |
| Eos | http://localhost:8082/actuator/health | Spring Boot actuator |
| Keycloak | http://localhost:8083/auth | Admin console: /auth/admin |
| Cohort Explorer API | http://localhost:8084/ | Requires Keycloak enabled |
| Cohort Explorer UI | http://localhost:8085/ | Angular SPA |

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

## Building Cohort Explorer (Phase 12, Optional)

No published Docker images exist upstream — they must be built from source.

```bash
git clone https://github.com/highmed/cohort-explorer-backend
docker build -t YOUR_REGISTRY/cohort-explorer-backend:latest cohort-explorer-backend/

git clone https://github.com/highmed/cohort-explorer-frontend
docker build --build-arg ENVIRONMENT=deploy \
  -t YOUR_REGISTRY/cohort-explorer-frontend:latest cohort-explorer-frontend/
```

**Local development (no registry):** build directly into the cluster's Docker daemon instead:

```bash
eval $(minikube docker-env)
docker build -t cohort-explorer-backend:local cohort-explorer-backend/
docker build --build-arg ENVIRONMENT=deploy -t cohort-explorer-frontend:local cohort-explorer-frontend/
```

Set the image coordinates in your values file and enable the components:

```yaml
cohort-explorer-backend:
  enabled: true
  image:
    repository: YOUR_REGISTRY/cohort-explorer-backend  # or cohort-explorer-backend for local
    tag: "latest"
    pullPolicy: IfNotPresent                            # or Never for local

cohort-explorer-frontend:
  enabled: true
  image:
    repository: YOUR_REGISTRY/cohort-explorer-frontend
    tag: "latest"
    pullPolicy: IfNotPresent

postgres:
  numportal:
    enabled: true
  keycloak:
    enabled: true

keycloak:
  enabled: true
```

The `crr` Keycloak realm and both clients (`num-portal`, `num-portal-webapp`) are created
automatically on first Keycloak startup — no manual admin console steps required.
See [NEXT_STEPS.md](NEXT_STEPS.md) for full prerequisites and secret keys needed.

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
