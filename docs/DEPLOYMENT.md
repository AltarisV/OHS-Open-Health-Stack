# Deployment Guide: Open Health Stack

## Quick Start

### Prerequisites

Before deploying OHS, ensure your Kubernetes cluster meets these requirements:

- **Kubernetes**: 1.24 or later
- **Helm**: 3.12 or later
- **kubectl**: Configured and authenticated to your cluster
- **Persistent Storage**: At least 100 GiB available (10 GiB EHRbase + 50 GiB Eos OMOP + buffers)
- **Ingress Controller**: Installed and configured (Nginx, Traefik, or cloud-native)
- **TLS/Certificates**: (Optional but recommended for production)
  - If using cert-manager: install cert-manager v1.13+
  - Or: pre-create TLS secret for your domain

### Cluster Topology (Recommended)

```
┌─────────────────────────────────────────┐
│      Kubernetes Cluster (3+ nodes)      │
├─────────────────────────────────────────┤
│  Control Plane (HA): 3 nodes             │
│  Worker Nodes: 3+ (for stateless apps)   │
│  Storage: PersistentVolumes (100+ GiB)   │
│  Networking: Ingress Controller active   │
└─────────────────────────────────────────┘
```

---

## Installation Steps

### Step 1: Prepare Namespace & RBAC

```bash
# Create dedicated namespace (optional but recommended)
kubectl create namespace ohs
kubectl label namespace ohs name=ohs

# Set current context
kubectl config set-context --current --namespace=ohs
```

### Step 2: Install the Required Operators

The chart does **not** install the CloudNativePG or MongoDB Community operators. Install them cluster-wide before deploying OHS:

```bash
# CloudNativePG operator (PostgreSQL)
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cnpg-system cnpg/cloudnative-pg --namespace cnpg-system --create-namespace

# MongoDB Community Operator
# watchNamespace=ohs scopes the operator to the OHS namespace; use "*" to watch all.
helm repo add mongodb https://mongodb.github.io/helm-charts
helm install mongodb-operator mongodb/community-operator \
  --namespace mongodb-operator --create-namespace \
  --set operator.watchNamespace=ohs
```

### Step 3: Clone or Navigate to OHS Repository

```bash
# If cloning for the first time:
git clone https://github.com/yourusername/ohs-open-health-stack.git
cd ohs-open-health-stack

# Or if already cloned:
cd /path/to/ohs-open-health-stack
```

### Step 4: Customize Configuration

**Create a custom values file** (never edit values.yaml directly):

```bash
cp values.yaml values-prod.yaml
# Or for development:
cp values.yaml values-dev.yaml
# Optional local Docker Desktop profile (already provided in this repo):
cp values-local.yaml values-local.override.yaml
```

**Edit your custom values file** with your environment details:

```yaml
# values-prod.yaml (example)

global:
  domain: "yourdomain.org"  # CHANGE_ME: your actual domain
  environment: "production"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: "ohs.yourdomain.org"
      paths:
        - path: "/ehrbase"
          pathType: "Prefix"
          service: "ohs-ehrbase"
          port: 8080

# Set resource limits appropriate for your cluster
ehrbase:
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

openfhir:
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "2Gi"

eos:
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

# Configure database storage
postgres:
  ehrbase:
    storage: "20Gi"  # Adjust based on expected EHR data volume
  eos:
    storage: "100Gi"  # OMOP CDM requires more space

mongodb:
  openfhir:
    storage: "20Gi"

# Set secure passwords via Kubernetes Secrets (see next section)
ehrbase:
  auth:
    password: "CHANGE_ME_SECURE_PASSWORD"
  database:
    password: "CHANGE_ME_DATABASE_PASSWORD"

openfhir:
  database:
    mongoUri: "mongodb://openfhir:CHANGE_ME_PASSWORD@..."

eos:
  database:
    password: "CHANGE_ME_DATABASE_PASSWORD"
```

### Step 5: Create the `ohs-credentials` Secret

The chart references the `ohs-credentials` secret but does not create it. It must exist before `helm install`.

```bash
cp .env.example .env
# edit .env with your passwords
bash create-secret.sh
```

`create-secret.sh` reads `.env` and assembles the full MongoDB URI automatically. `.env` is gitignored; `.env.example` is the committed template.

The complete list of required keys and the Sealed Secrets / External Secrets Operator / SOPS alternatives for production are documented in **[SECRETS.md](SECRETS.md)**.

> **Note:** The password in `openfhir-mongo-uri` **must exactly match** `mongodb.openfhir.userPassword` in your values file, or openFHIR fails SCRAM authentication at startup.

### Step 6: Validate Helm Chart

```bash
# Lint the chart for syntax errors
helm lint .

# Generate and review manifests (without deploying)
helm template ohs . -f values-prod.yaml > /tmp/ohs-manifests.yaml
cat /tmp/ohs-manifests.yaml | head -100

# Optional: validate YAML syntax with kubeval
helm template ohs . -f values-prod.yaml | kubeval --strict
```

### Step 7: Deploy with Helm

```bash
# IMPORTANT: Always package first - vocab/ is 4.4 GB and will OOM-kill helm if
# you pass "." directly. Packaging uses .helmignore to exclude vocab/.
helm package . -d /tmp/

# Dry-run first (simulates deployment without applying changes)
helm install ohs /tmp/ohs-0.1.0.tgz \
  --namespace ohs \
  --values values-prod.yaml \
  --dry-run \
  --debug

# If dry-run looks good, proceed with actual install
helm install ohs /tmp/ohs-0.1.0.tgz \
  --namespace ohs \
  --values values-prod.yaml

# Optional local Docker Desktop install profile
helm upgrade --install ohs . \
  --namespace ohs \
  --values values.yaml \
  --values values-local.yaml \
  --timeout 15m

# Monitor installation progress
watch kubectl get pods -n ohs

# Check installation status
helm status ohs -n ohs
helm get values ohs -n ohs
```

### Step 8: Wait for Components to Initialize

```bash
# Database operators typically start first (2-5 minutes)
kubectl get pods -n ohs -l app=postgres-operator
kubectl get pods -n ohs -l app=mongodb-operator

# Database clusters initialization (5-10 minutes)
kubectl get cloudnativepgclusters -n ohs
kubectl get mongodbcommunity -n ohs

# Application deployments (10-20 minutes total)
kubectl rollout status deployment/ohs-ehrbase -n ohs
kubectl rollout status deployment/ohs-openfhir -n ohs
kubectl rollout status deployment/ohs-eos -n ohs

# All pods should eventually show "Running"
kubectl get pods -n ohs -w  # -w for watch mode
```

---

## Verification Checklist

### All Pods Running

```bash
kubectl get pods -n ohs

# Expected output (simplified):
# NAME                                    READY   STATUS    RESTARTS   AGE
# ohs-cloudnative-pg-operator-...         1/1     Running   0          5m
# ohs-mongodb-operator-...                1/1     Running   0          5m
# postgres-cluster-1                      1/1     Running   0          3m
# mongodb-cluster-0                       1/1     Running   0          3m
# ohs-ehrbase-0                           1/1     Running   0          2m
# ohs-openfhir-0                          1/1     Running   0          2m
# ohs-eos-0                               1/1     Running   0          2m
```

### Database Clusters Healthy

```bash
# PostgreSQL cluster status
kubectl get cloudnativepgclusters -n ohs
# READY should be 3/3

# MongoDB cluster status
kubectl get mongodbcommunity -n ohs
# READY should be 3/3
```

### Services Accessible

```bash
# Check services
kubectl get svc -n ohs

# Verify endpoints are assigned
kubectl get endpoints -n ohs | grep -E 'ehrbase|openfhir|eos'
```

### Health Endpoints Responding

Port-forwards, health checks, and the full end-to-end workflow (EHR → composition → OMOP → Cohort Explorer) are documented in **[VERIFICATION.md](VERIFICATION.md)**. Note that Eos listens on `8081`, not `8080`, and EHRbase APIs are under the `/ehrbase` path prefix.

### Ingress Configured

```bash
# Check Ingress resource
kubectl get ingress -n ohs
kubectl describe ingress ohs-ingress -n ohs

# Test DNS resolution (if configured)
nslookup ohs.yourdomain.org
# Should resolve to your Ingress controller IP
```

### Logs Verification

```bash
# Check EHRbase logs for errors
kubectl logs -n ohs -l app=ehrbase --tail=50

# Check openFHIR logs
kubectl logs -n ohs -l app=openfhir --tail=50

# Check Eos logs
kubectl logs -n ohs -l app=eos --tail=50

# Follow logs in real-time
kubectl logs -n ohs -l app=ehrbase -f
```

---

## First Deployment Tests

See **[VERIFICATION.md](VERIFICATION.md)** for the complete functional test suite: creating an EHR, uploading a template, submitting a blood pressure composition, running the Eos OMOP transformation, and viewing the result in the Cohort Explorer.

---

## Post-Deployment Configuration

### Configure TLS/HTTPS

If using cert-manager:

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.org
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Update Ingress to use TLS
kubectl patch ingress ohs-ingress -n ohs --type merge -p \
'{"spec":{"tls":[{"hosts":["ohs.yourdomain.org"],"secretName":"ohs-tls"}]}}'
```

### Enable Monitoring (Optional)

```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Update OHS values to enable monitoring
helm package . -d /tmp/ && helm upgrade ohs /tmp/ohs-0.1.0.tgz \
  --namespace ohs \
  --values values-prod.yaml \
  --set monitoring.enabled=true
```

### Configure External Secret Management

See Step 5 above for Sealed Secrets or External Secrets Operator setup.

---

## Troubleshooting

### Problem: cohort-explorer-backend CrashLoopBackOff (`num-attachment` schema missing)

`ProjectMapper` unconditionally requires `AttachmentService`, which needs the `num-attachment`
schema to exist in the `numportal` database. Flyway only creates tables, not schemas, so the
schema must be created once after the postgres cluster is ready. The one-time setup script is
in [GETTING_STARTED.md](GETTING_STARTED.md#one-time-create-the-attachment-schema).

### Problem: cohort-explorer-frontend shows "authentication service" error

The Angular production build loads `config.deploy.json`, not `config.json`. Both files
are now mounted from the same ConfigMap - but if you built an older chart version, only
`config.json` was mounted, leaving `config.deploy.json` with Azure DevOps placeholders
(`#{auth_baseUrl}` etc.) which breaks OIDC init. Upgrade to the latest chart revision.

### Problem: Pods in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n ohs <pod-name> --previous

# Check events
kubectl describe pod -n ohs <pod-name>

# Common causes:
# - Incorrect environment variables
# - Database connection failure
# - Resource limits too low
```

### Problem: Persistent Volumes Not Binding

```bash
# Check PVC status
kubectl get pvc -n ohs
kubectl describe pvc -n ohs <pvc-name>

# Ensure storage class exists
kubectl get storageclass

# If missing, create default storage class (cloud-provider specific)
```

### Problem: Ingress Not Routing Traffic

```bash
# Check Ingress status
kubectl describe ingress ohs-ingress -n ohs

# Verify Ingress controller is running
kubectl get pods -n ingress-nginx  # or -n traefik, depending on controller

# Check DNS resolution
nslookup ohs.yourdomain.org
```

### Problem: Database Initialization Slow

CloudNativePG and MongoDB operators perform initial setup (5-15 minutes):

```bash
# Check operator logs
kubectl logs -n ohs -l app=postgres-operator -f
kubectl logs -n ohs -l app=mongodb-operator -f

# Check cluster status
kubectl describe cloudnativepgcluster postgres-cluster -n ohs
kubectl describe mongodbcommunity mongodb-cluster -n ohs
```

### Problem: Authentication Failures

```bash
# Verify credentials are correctly set in Kubernetes Secret
kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data}' | base64 -d

# Update EHRbase password
kubectl patch secret ohs-credentials -n ohs \
  -p '{"data":{"ehrbase-user-password":"'$(echo -n 'newpassword' | base64)'"}}'

# Restart pods to pick up new secrets
kubectl rollout restart deployment/ohs-ehrbase -n ohs
```

---

## Upgrades & Updates

### Updating OHS Components

```bash
# Update to new OHS version
git pull origin main
git checkout v0.2.0  # tag name

# Helm upgrade
helm package . -d /tmp/ && helm upgrade ohs /tmp/ohs-0.1.0.tgz \
  --namespace ohs \
  --values values-prod.yaml

# Monitor upgrade progress
kubectl rollout status deployment/ohs-ehrbase -n ohs
kubectl rollout status deployment/ohs-openfhir -n ohs
kubectl rollout status deployment/ohs-eos -n ohs
```

### Database Backup & Restore

**CloudNativePG Backup:**
```bash
# Check backup status
kubectl get backups -n ohs

# Trigger manual backup
kubectl annotate cloudnativepgcluster postgres-cluster -n ohs \
  'cluster.cnpg.io/backup=true' --overwrite

# Restore from backup (advanced)
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster-restored
spec:
  bootstrap:
    recovery:
      source: cluster-backup
  externalClusters:
  - name: cluster-backup
    connectionParameters:
      host: minio.example.org
EOF
```

---

## Performance Tuning

### Scaling Components

```bash
# Scale EHRbase replicas
kubectl scale deployment ohs-ehrbase --replicas=3 -n ohs

# Scale database replicas
kubectl patch cloudnativepgcluster postgres-cluster -n ohs \
  -p '{"spec":{"instances":5}}'
```

### Adjusting Resource Limits

```bash
# Update resource limits in values file and upgrade
helm package . -d /tmp/ && helm upgrade ohs /tmp/ohs-0.1.0.tgz \
  --namespace ohs \
  --values values-prod.yaml \
  --set ehrbase.resources.limits.cpu=4000m
```

---

## Uninstallation

> **Data safety:** The PostgreSQL and MongoDB cluster resources are annotated with
> `helm.sh/resource-policy: keep`. This means `helm uninstall` intentionally does **not**
> delete those clusters or their PVCs - your data survives the Helm release removal.
> Delete the clusters manually only when you are sure you no longer need the data.

```bash
# Remove OHS Helm release (databases are kept - see note above)
helm uninstall ohs -n ohs

# Optional: delete the database clusters and their PVCs (IRREVERSIBLE - backup first)
# NOTE: postgres-eos-cluster only exists when postgres.eos.sharedCluster=false. With the
# shipped default (true), Eos shares postgres-cluster, so omit the postgres-eos-cluster lines.
kubectl delete cluster postgres-cluster postgres-eos-cluster -n ohs
kubectl delete mongodbcommunity mongodb-cluster -n ohs
kubectl delete pvc -n ohs -l cnpg.io/cluster=postgres-cluster
kubectl delete pvc -n ohs -l cnpg.io/cluster=postgres-eos-cluster

# Optional: delete the namespace entirely
kubectl delete namespace ohs
```

> **Reinstalling after uninstall:** Because the database clusters are kept, use
> `helm upgrade --install` instead of `helm install` to avoid "already exists" errors:
> ```bash
> helm package . -d /tmp/ && helm upgrade --install ohs /tmp/ohs-0.1.0.tgz -n ohs -f values.yaml
> ```

---

## Support & Documentation

- **EHRbase Docs**: https://docs.ehrbase.org/
- **openFHIR Docs**: https://github.com/openfhir/openfhir
- **Eos (OMOP Bridge)**: https://github.com/SevKohler/Eos
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Helm Docs**: https://helm.sh/docs/

---

## Production Deployment Notes

These notes were discovered during real deployment and address issues not covered above.

Operator pre-installation (Step 2) and the `ohs-credentials` secret (Step 5 / [SECRETS.md](SECRETS.md)) are already covered in the installation steps above.

### PostgreSQL Cluster Persistence Across Upgrades

The `postgres-cluster.yaml` Cluster resource is annotated with `helm.sh/resource-policy: keep`, so `helm uninstall` and `helm upgrade` do **not** delete the cluster or its PVCs - data survives. The CNPG operator manages the cluster lifecycle independently of the Helm release.

- To fully remove a cluster (and its data), delete it manually: `kubectl delete cluster postgres-cluster -n ohs`.
- Because the cluster is kept, always reinstall with `helm upgrade --install` to avoid "already exists" errors (see Uninstallation above).

### Service Ports

See the [Service Ports table in ARCHITECTURE.md](ARCHITECTURE.md#service-ports). Key gotcha: Eos listens on **8081** (`server.port: 8081` in its `application.yml`), not 8080 - its probes and service `targetPort` must use 8081.

### CNPG Service Name

CloudNativePG creates the read-write service as `<cluster-name>-rw`, not `<cluster-name>`. Use `postgres-cluster-rw.ohs.svc.cluster.local` as the database hostname in all application configs.

### Eos OMOP CDM Setup

Eos bridges openEHR to the OMOP Common Data Model. On first startup, Hibernate (`ddl-auto: update`) automatically creates entity-mapped tables. However, the OMOP **vocabulary tables** (CONCEPT, VOCABULARY, DOMAIN, etc.) are not created automatically and must be populated from [Athena](https://athena.ohdsi.org/) before mappings will function correctly. See VERIFICATION.md for the loading procedure.

### MongoDB Image

MongoDB Alpine variants (`mongo:x.y.z-alpine`) were discontinued after version 4.4. The MongoDB Community Operator uses `docker.io/mongodb/mongodb-community-server:<version>-ubi8` automatically when no custom image is specified - do not override the image in `statefulSet.spec.template.spec.containers`.

### MongoDB Operator StatefulSet Caution

Do not override `selector.matchLabels`, pod template `metadata.labels`, or `serviceName` inside `statefulSet.spec` in `mongodb-cluster.yaml`. The operator assigns these itself; custom values break the operator-managed service-to-pod selector and the pod will not be discovered.

