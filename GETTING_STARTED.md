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
helm package . -d /tmp/ && \
helm upgrade --install ohs /tmp/ohs-0.1.0.tgz -f values.yaml -f values-minikube.yaml -n ohs \
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

# Apply config changes (use packaged tarball to avoid loading large data files)
helm package . -d /tmp/ && helm upgrade ohs /tmp/ohs-0.1.0.tgz -f values.yaml -n ohs
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

**Local development (no registry):** build on the host Docker daemon (full network speed), then load into minikube:

```bash
# Build on host (fast — full network speed for Maven/npm downloads)
docker build -t cohort-explorer-backend:local cohort-explorer-backend/
docker build --build-arg ENVIRONMENT=deploy -t cohort-explorer-frontend:local cohort-explorer-frontend/

# Load into minikube's Docker daemon
eval $(minikube docker-env -u)  # ensure host daemon is active for save
docker save cohort-explorer-backend:local -o /tmp/backend.tar
docker save cohort-explorer-frontend:local -o /tmp/frontend.tar

eval $(minikube docker-env) && export DOCKER_API_VERSION=1.43
docker load -i /tmp/backend.tar && rm /tmp/backend.tar
docker load -i /tmp/frontend.tar && rm /tmp/frontend.tar
```

> **Note:** Do not build directly inside minikube's Docker daemon (`eval $(minikube docker-env)`) — Maven and npm will download dependencies through minikube's NAT layer at only a few kB/s.

> **Note for Docker API mismatch:** If you see `client version X is too new`, set `export DOCKER_API_VERSION=1.43` before running docker commands against minikube.

**Known build requirements for cohort-explorer-backend:**
- Requires `.config/checkstyle.xml` and `.git/` to be present in the build context
- Use `-Dmaven.test.skip=true` and `-Dgit.skip=true` flags (tests require Docker/ClamAV)
- The Dockerfile in this repo already includes these flags

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

> **Important — frontend config URLs must be browser-accessible:** The `cohort-explorer-frontend.config.auth.baseUrl` and `cohort-explorer-frontend.config.api.baseUrl` values are fetched by the user's browser at runtime, not from inside the cluster. When port-forwarding, set them to `http://localhost:<port>` (e.g. `http://localhost:8083/auth` and `http://localhost:8084/num-portal`). See `values-minikube.yaml` for an example.

### One-time: Create the attachment schema

The backend requires a `num-attachment` schema in the `numportal` database. This must be
created once after the postgres cluster is ready (Flyway only creates tables, not schemas):

```bash
# Find the primary pod (the one not in recovery)
for i in 1 2 3; do
  PRIMARY=$(kubectl exec -n ohs postgres-cluster-$i -- psql -U postgres -d numportal \
    -c 'SELECT pg_is_in_recovery();' 2>/dev/null | grep -c " f")
  if [ "$PRIMARY" -gt 0 ]; then
    kubectl exec -n ohs postgres-cluster-$i -- psql -U postgres -d numportal \
      -c 'CREATE SCHEMA IF NOT EXISTS "num-attachment"; GRANT ALL ON SCHEMA "num-attachment" TO numportal;'
    break
  fi
done
```

### First login: Create a user in the `crr` realm

The `crr` realm has no default users. Create one via the Keycloak Admin API
(requires the Keycloak port-forward to be running on 8083):

```bash
KC_PASS=$(kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data.keycloak-admin-password}' | base64 -d)
TOKEN=$(curl -s -X POST http://localhost:8083/auth/realms/master/protocol/openid-connect/token \
  -d "client_id=admin-cli&grant_type=password&username=admin&password=$KC_PASS" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Create user (change username/email/password as needed)
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "http://localhost:8083/auth/admin/realms/crr/users" \
  -d '{"username":"admin","email":"admin@example.com","firstName":"Admin","lastName":"User",
       "enabled":true,"credentials":[{"type":"password","value":"admin123","temporary":false}]}'

# Assign the SUPER_ADMIN realm role
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8083/auth/admin/realms/crr/users?username=admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
ROLE=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8083/auth/admin/realms/crr/roles/SUPER_ADMIN")
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "http://localhost:8083/auth/admin/realms/crr/users/$USER_ID/role-mappings/realm" \
  -d "[$(echo $ROLE | python3 -c 'import sys,json; d=json.load(sys.stdin); import json as j; print(j.dumps({"id":d["id"],"name":d["name"]}))')]"
```

Alternatively, use the Keycloak Admin Console at `http://localhost:8083/auth/admin`
(login as `admin` with the value from `ohs-credentials/keycloak-admin-password`).

### Port-forward stability

`kubectl port-forward` can die silently after periods of inactivity. Use this
keepalive loop to automatically restart any that have stopped:

```bash
while true; do
  ss -tlnp | grep -q 8083 || kubectl port-forward svc/ohs-keycloak 8083:8080 -n ohs &>/tmp/kc-pf.log &
  ss -tlnp | grep -q 8084 || kubectl port-forward svc/ohs-cohort-explorer-backend 8084:8090 -n ohs &>/tmp/backend-pf.log &
  ss -tlnp | grep -q 8085 || kubectl port-forward svc/ohs-cohort-explorer-frontend 8085:80 -n ohs &>/tmp/frontend-pf.log &
  sleep 10
done
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
