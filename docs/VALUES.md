# Values Reference: Open Health Stack

This document is a reference for the Helm chart values. `values.yaml` (and
`values-local.yaml` for the Docker Desktop profile) is the canonical source of truth — when
this page and `values.yaml` disagree, `values.yaml` wins. In-cluster hostnames below assume
the release is installed as `ohs` in namespace `ohs`; substitute your own if you change either.

## Table of Contents

1. [Global Configuration](#global-configuration)
2. [Database Operators](#database-operators)
3. [PostgreSQL Clusters](#postgresql-clusters)
4. [MongoDB Clusters](#mongodb-clusters)
5. [EHRbase](#ehrbase)
6. [openFHIR](#openfhir)
7. [Eos (OMOP Bridge)](#eos-omop-bridge)
8. [openEHRTool-v2](#openehrtool-v2)
9. [Placeholder Components](#placeholder-components)
10. [Networking & Ingress](#networking--ingress)
11. [RBAC & Security](#rbac--security)
12. [Monitoring & Logging](#monitoring--logging)

---

## Global Configuration

### `global`

Shared settings applied across all subcharts.

```yaml
global:
  domain: string                    # (REQUIRED) Base domain for the platform
                                    # Example: "example.org"
                                    # CHANGE_ME: your actual domain
  
  environment: string               # Deployment environment
                                    # Options: "development", "staging", "production"
                                    # Default: "development"
  
  timezone: string                  # Timezone for all components
                                    # Default: "UTC"
                                    # Examples: "Europe/Berlin", "US/Eastern"
  
  imagePullPolicy: string           # Default image pull policy
                                    # Options: "Always", "IfNotPresent", "Never"
                                    # Default: "IfNotPresent"
  
  podSecurityContext:
    runAsNonRoot: boolean           # Run containers as non-root (security best practice)
                                    # Default: false (CHANGE_ME to true for production)
    fsGroup: integer                # File system group ID
                                    # Default: 1000
```

### Example: Production Configuration

```yaml
global:
  domain: "ohs.hospital.org"
  environment: "production"
  timezone: "Europe/Berlin"
  imagePullPolicy: "IfNotPresent"
  podSecurityContext:
    runAsNonRoot: true
    fsGroup: 1000
```

---

## Database Operators

### `cloudnative-pg`

CloudNativePG Operator for PostgreSQL cluster management.

```yaml
cloudnative-pg:
  enabled: boolean                  # Enable PostgreSQL operator
                                    # Default: true
  
  version: string                   # Operator version (PIN_VERSION)
                                    # Current: "1.21.0"
                                    # Check: https://github.com/cloudnative-pg/cloudnative-pg/releases
  
  cnpg:
    crds:
      create: boolean               # Install CloudNativePG CRDs
                                    # Default: true
```

### `mongodb-operator`

MongoDB Community Operator for MongoDB cluster management.

```yaml
mongodb-operator:
  enabled: boolean                  # Enable MongoDB operator
                                    # Default: true
  
  version: string                   # Operator version (PIN_VERSION)
                                    # Current: "0.8.0"
                                    # Check: https://github.com/mongodb/mongodb-kubernetes-operator/releases
```

---

## PostgreSQL Clusters

### `postgres.ehrbase`

PostgreSQL cluster for EHRbase EHR storage.

```yaml
postgres:
  enabled: boolean                  # Enable PostgreSQL cluster provisioning
                                    # Default: true
  
  ehrbase:
    enabled: boolean                # Enable EHRbase PostgreSQL cluster
                                    # Default: true
    
    storage: string                 # Persistent volume size for data
                                    # Default: "10Gi"
                                    # CHANGE_ME: adjust for expected EHR data volume
                                    # (Rule of thumb: 100MB - 1GB per patient, 1000 patients = 100-1000GB)
    
    instances: integer              # Number of PostgreSQL replicas (HA)
                                    # Default: 3 (production minimum)
                                    # Development: 1-2 acceptable
    
    walStorage: string              # Write-Ahead Log (WAL) storage size
                                    # Default: "5Gi"
                                    # Should be ~50% of main storage
    
    backupRetention: string         # How long to retain backups
                                    # Default: "30d" (30 days)
                                    # Format: "1d", "7d", "30d", "90d", etc.
    
    primaryUpdateStrategy: string   # Upgrade strategy for primary node
                                    # Options: "unsupervised" (automated), "rollingUpdate" (manual)
                                    # Default: "unsupervised"
```

### `postgres.eos`

PostgreSQL cluster for Eos OMOP CDM data warehouse.

```yaml
postgres:
  eos:
    enabled: boolean                # Enable Eos PostgreSQL cluster
                                    # Default: true
    
    sharedCluster: boolean          # Share cluster with EHRbase (same cluster, different schema)
                                    # If true: uses postgres.ehrbase cluster
                                    # If false: creates separate cluster for Eos
                                    # Default: true (cost-effective for MVP)
    
    storage: string                 # Persistent volume size
                                    # Default: "50Gi"
                                    # CHANGE_ME: OMOP CDM is larger; 50-200GB typical
    
    instances: integer              # Number of replicas
                                    # Default: 2
                                    # (Can be lower than EHRbase for analytics workload)
```

---

## MongoDB Clusters

### `mongodb.openfhir`

MongoDB cluster for openFHIR FHIR resource storage.

```yaml
mongodb:
  enabled: boolean                  # Enable MongoDB cluster provisioning
                                    # Default: true
  
  openfhir:
    enabled: boolean                # Enable openFHIR MongoDB cluster
                                    # Default: true
    
    storage: string                 # Persistent volume size
                                    # Default: "20Gi"
                                    # CHANGE_ME: adjust for expected FHIR document volume
    
    replicas: integer               # Number of MongoDB replicas (HA)
                                    # Default: 3
                                    # Minimum: 1 (development), 3 (production)
    
    rootPassword: string            # MongoDB root password
                                    # Default: "CHANGE_ME_SECURE_PASSWORD"
                                    # CHANGE_ME: use strong password or inject via Secret
    
    persistence:
      enabled: boolean              # Enable persistent volume for MongoDB data
                                    # Default: true (required for production)
```

---

## EHRbase

### `ehrbase`

EHR storage system (openEHR implementation).

```yaml
ehrbase:
  enabled: boolean                  # Enable EHRbase deployment
                                    # Default: true
  
  replicaCount: integer             # Number of EHRbase pods (for HA and load balancing)
                                    # Default: 2
                                    # Production minimum: 2, typical: 2-3
  
  image:
    repository: string              # Docker image repository
                                    # Default: "ehrbase/ehrbase"
    
    tag: string                     # Image tag (PIN_VERSION)
                                    # Current: "2.31.0"
                                    # Check: https://hub.docker.com/r/ehrbase/ehrbase/tags
    
    pullPolicy: string              # Image pull policy
                                    # Default: "IfNotPresent" (uses global)
  
  service:
    type: string                    # Kubernetes service type
                                    # Options: "ClusterIP" (internal), "LoadBalancer" (external), "NodePort"
                                    # Default: "ClusterIP"
    
    port: integer                   # Service port (external/internal)
                                    # Default: 8080
    
    targetPort: integer             # Container port (application listens here)
                                    # Default: 8080
  
  ingress:
    enabled: boolean                # Enable Ingress routing
                                    # Default: true
    
    path: string                    # URL path prefix
                                    # Default: "/ehrbase"
                                    # Example: requests to https://ohs.example.org/ehrbase route here
    
    pathType: string                # Ingress path matching type
                                    # Options: "Exact", "Prefix"
                                    # Default: "Prefix"
  
  resources:
    requests:
      cpu: string                   # Requested CPU (scheduler minimum)
                                    # CHANGE_ME: e.g., "500m" (0.5 CPU cores)
      memory: string                # Requested memory
                                    # CHANGE_ME: e.g., "1Gi"
    
    limits:
      cpu: string                   # Maximum CPU allowed
                                    # CHANGE_ME: e.g., "2000m" (2 CPU cores)
      memory: string                # Maximum memory allowed
                                    # CHANGE_ME: e.g., "4Gi"
  
  auth:
    enabled: boolean                # Enable authentication (recommended)
                                    # Default: true
    
    username: string                # Basic auth username
                                    # Default: "ehrbase_user"
                                    # CHANGE_ME: use strong username
    
    password: string                # Basic auth password
                                    # Default: "CHANGE_ME_SECURE_PASSWORD"
                                    # CHANGE_ME: inject via Kubernetes Secret in production
    
    type: string                    # Authentication type
                                    # Options: "BASIC" (username/password), "OAUTH2" (OAuth2 provider)
                                    # Default: "BASIC"
  
  database:
    host: string                    # PostgreSQL host/service name (CNPG read-write endpoint)
                                    # Default: "postgres-cluster-rw.ohs.svc.cluster.local"
                                    # CHANGE_ME: update namespace if not 'ohs'
    
    port: integer                   # PostgreSQL port
                                    # Default: 5432
    
    name: string                    # Database name
                                    # Default: "ehrbase"
    
    username: string                # Database username
                                    # Default: "ehrbase"
    
    password: string                # Database password
                                    # Default: "CHANGE_ME_DATABASE_PASSWORD"
                                    # CHANGE_ME: inject via Secret
  
  livenessProbe:
    httpGet:
      path: string                  # Health check endpoint
                                    # Default: "/health"
      port: integer                 # Port for health check
                                    # Default: 8080
    
    initialDelaySeconds: integer    # Wait before first probe
                                    # Default: 30 seconds
    
    periodSeconds: integer          # Probe interval
                                    # Default: 10 seconds
  
  readinessProbe:
    httpGet:
      path: string                  # Readiness endpoint
      port: integer
    
    initialDelaySeconds: integer    # Default: 20
    periodSeconds: integer          # Default: 5
```

### Example: Production EHRbase Configuration

```yaml
ehrbase:
  enabled: true
  replicaCount: 3
  image:
    repository: "ehrbase/ehrbase"
    tag: "2.31.0"
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  auth:
    username: "ehrbase_admin"
    password: "CHANGE_ME_STRONG_PASSWORD"  # Inject via Secret!
  database:
    host: "postgres-cluster-rw.ohs.svc.cluster.local"
    password: "CHANGE_ME_DB_PASSWORD"  # Inject via Secret!
```

---

## openFHIR

### `openfhir`

FHIR server with EHR-to-FHIR mapping bridge.

```yaml
openfhir:
  enabled: boolean                  # Enable openFHIR deployment
                                    # Default: true
  
  replicaCount: integer             # Number of openFHIR pods
                                    # Default: 2
  
  image:
    repository: string              # Docker image
                                    # Default: "openfhir/openfhir"
    tag: string                     # Image tag (PIN_VERSION)
                                    # Current: "2.2.1"
                                    # Check: https://hub.docker.com/r/openfhir/openfhir/tags
    pullPolicy: string
  
  service:
    type: string                    # Default: "ClusterIP"
    port: integer                   # Default: 8080
    targetPort: integer             # Default: 8080
  
  ingress:
    enabled: boolean                # Default: true
    path: string                    # Default: "/openfhir"
    pathType: string                # Default: "Prefix"
  
  resources:
    requests:
      cpu: string                   # CHANGE_ME: e.g., "500m"
      memory: string                # CHANGE_ME: e.g., "1Gi"
    limits:
      cpu: string                   # CHANGE_ME: e.g., "2000m"
      memory: string                # CHANGE_ME: e.g., "2Gi"
  
  fhir:
    versions: array                 # FHIR versions to support
                                    # Default: ["STU3", "R4", "R4B"]
                                    # Options: "STU3" (outdated), "R4" (current), "R4B", "R5" (draft)
  
  database:
    mongoUri: string                # MongoDB connection string. In practice this is injected
                                    # from ohs-credentials/openfhir-mongo-uri (see SECRETS.md),
                                    # not set here. Service name: "mongodb-cluster-svc".
                                    # e.g. "mongodb://openfhir:PASSWORD@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir"
  
  ehrbaseIntegration:
    enabled: boolean                # Enable two-way sync with EHRbase
                                    # Default: true
    
    baseUrl: string                 # EHRbase API endpoint
                                    # Default: "http://ohs-ehrbase.ohs.svc.cluster.local:8080/ehrbase"
                                    # CHANGE_ME: update namespace if not 'ohs'
    
    username: string                # EHRbase API username
                                    # Default: "ehrbase_user"
    
    password: string                # EHRbase API password
                                    # Default: "CHANGE_ME_SECURE_PASSWORD"
                                    # CHANGE_ME: inject via Secret
  
  livenessProbe:
    httpGet:
      path: string                  # Default: "/health"
      port: integer                 # Default: 8080
    initialDelaySeconds: integer    # Default: 30
    periodSeconds: integer          # Default: 10
```

> **openFHIR is a FHIRConnect mapping engine, not a FHIR REST server** — there is no
> `/fhir/Patient` resource API. Liveness is `GET /health`; see VERIFICATION.md.

---

## Eos (OMOP Bridge)

### `eos`

ETL tool for transforming EHR data to OMOP CDM.

```yaml
eos:
  enabled: boolean                  # Enable Eos deployment
                                    # Default: true
  
  replicaCount: integer             # Number of Eos pods (typically 1 for batch jobs)
                                    # Default: 1
  
  image:
    repository: string              # Docker image
                                    # Default: "ghcr.io/sevkohler/eos"
    tag: string                     # Image tag - upstream only publishes "latest"
                                    # Default: "latest" (pin to a digest for production)
                                    # Workflow: https://github.com/SevKohler/Eos
    pullPolicy: string
  
  service:
    type: string                    # Default: "ClusterIP"
    port: integer                   # Default: 8081 (Eos listens on 8081, NOT 8080)
    targetPort: integer             # Default: 8081
  
  ingress:
    enabled: boolean                # Default: true
    path: string                    # Default: "/eos"
    pathType: string
  
  resources:
    requests:
      cpu: string                   # CHANGE_ME: e.g., "500m"
      memory: string                # CHANGE_ME: e.g., "1Gi"
    limits:
      cpu: string                   # CHANGE_ME: e.g., "2000m"
      memory: string                # CHANGE_ME: e.g., "4Gi"
  
  database:
    host: string                    # PostgreSQL host (CNPG read-write endpoint)
                                    # Default: "postgres-cluster-rw.ohs.svc.cluster.local"
                                    # (shared with EHRbase when postgres.eos.sharedCluster=true)
    port: integer                   # Default: 5432
    
    name: string                    # Database/schema name
                                    # Default: "eos_omop"
                                    # Contains: OMOP CDM v5.4 tables
    
    username: string                # Database user
                                    # Default: "eos"
    
    password: string                # Database password
                                    # Default: "CHANGE_ME_DATABASE_PASSWORD"
                                    # CHANGE_ME: inject via Secret
  
  ehrbase:
    baseUrl: string                 # EHRbase API endpoint
                                    # Default: "http://ohs-ehrbase.ohs.svc.cluster.local:8080/ehrbase/"
    
    username: string                # EHRbase username
                                    # Default: "ehrbase_user"
    
    password: string                # EHRbase password
                                    # Default: "CHANGE_ME_SECURE_PASSWORD"
  
  omop:
    athenaVocabulariesPresent: boolean  # Informational only — upstream Eos has no runtime
                                        # toggle and reads the vocab tables directly. Concept
                                        # mapping works once Athena vocabularies are loaded into
                                        # eos_omop and the Eos pod is restarted. Default: false
    
    mappingFiles: string            # OMOP concept mapping files location
                                    # Default: "CHANGE_ME_REFERENCE_MAPPINGS"
                                    # Should point to ConfigMap or mounted path with mappings
  
  livenessProbe:
    httpGet:
      path: string                  # Default: "/health"
      port: integer
    initialDelaySeconds: integer    # Default: 30
    periodSeconds: integer          # Default: 10
```

---

## openEHRTool-v2

Deployed as three subcharts: `openehrtool-redis` (cache), `openehrtool-backend` (FastAPI), `openehrtool-frontend` (Vue3/nginx). All are enabled by default.

### `openehrtool-redis`

Embedded Redis 7 cache for activity logs and artefact ID storage. No authentication, persistence disabled, max memory 64 MB (LRU).

```yaml
openehrtool-redis:
  enabled: boolean                  # Default: true
  
  image:
    repository: string              # Default: "redis"
    tag: string                     # Default: "7-alpine"
    pullPolicy: string              # Default: "IfNotPresent"
  
  service:
    port: integer                   # Default: 6379
```

### `openehrtool-backend`

FastAPI backend (Python 3.11). Communicates with EHRbase and Redis.

```yaml
openehrtool-backend:
  enabled: boolean                  # Default: true
  
  image:
    repository: string              # Default: "localhost:5000/openehrtool-backend"
                                    # CHANGE_ME: update to your registry
    tag: string                     # Default: "ohs"
    pullPolicy: string              # Default: "Always"
  
  ehrbase:
    nodename: string                # EHRbase service hostname
                                    # Default: "ohs-ehrbase"
  
  redis:
    hostname: string                # Redis service hostname
                                    # Default: "ohs-openehrtool-redis"
    port: integer                   # Default: 6379
  
  ingress:
    enabled: boolean                # Default: true
    host: string                    # Ingress hostname for backend API
                                    # Default: "openehrtool"
                                    # Must match OPENEHRTOOL_BACKEND_HOSTNAME used at image build
  
  service:
    port: integer                   # Default: 5000
```

### `openehrtool-frontend`

Vue3/Vite SPA served by nginx. The backend hostname is baked into the bundle at image build time via `OPENEHRTOOL_BACKEND_HOSTNAME`.

```yaml
openehrtool-frontend:
  enabled: boolean                  # Default: true
  
  image:
    repository: string              # Default: "localhost:5000/openehrtool-frontend"
                                    # CHANGE_ME: update to your registry
    tag: string                     # Default: "ohs"
    pullPolicy: string              # Default: "Always"
  
  ingress:
    enabled: boolean                # Default: true
    host: string                    # Ingress hostname for the web UI
                                    # Default: "openehrtool"
  
  service:
    port: integer                   # Default: 80
```

### Building openEHRTool-v2 images

No published Docker images exist upstream. Use `scripts/build-images.sh`:

```bash
# Standard (registry)
OPENEHRTOOL_BACKEND_HOSTNAME=openehrtool \
  bash scripts/build-images.sh --registry your-registry.example.org:5000 --component openehrtool-backend
OPENEHRTOOL_BACKEND_HOSTNAME=openehrtool \
  bash scripts/build-images.sh --registry your-registry.example.org:5000 --component openehrtool-frontend

# Local Docker Desktop (no registry - shares host daemon)
bash scripts/build-images.sh --registry localhost:5000 --skip-push --component openehrtool-backend
OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
  bash scripts/build-images.sh --registry localhost:5000 --skip-push --component openehrtool-frontend
```

Required secret: `ohs-credentials/openehrtool-jwt-secret` (set `OPENEHRTOOL_JWT_SECRET` in `.env` before running `scripts/create-secret.sh`).

---

## Placeholder Components

### Remaining Staged Components

EHRsuction, Cohort Explorer, Keycloak, and openEHRTool-v2 are implemented and enabled in the
base/local profiles - see `values.yaml` and the per-component sections of GETTING_STARTED.md.
The following components are still staged.

```yaml
csv-to-openehr:
  enabled: false                    # CSV to openEHR - Bulk import
                                    # Implementation strategy TBD

better-platform:
  enabled: false                    # BETTER Platform - External reference
  externalEndpoint: string          # External BETTER endpoint
                                    # Default: "https://better.charité.example.org"
                                    # CHANGE_ME: update to actual endpoint
                                    # Not deployed by Helm (external system)
```

---

## Networking & Ingress

### `ingress`

Kubernetes Ingress configuration for external API access.

```yaml
ingress:
  enabled: boolean                  # Enable Ingress routing
                                    # Default: true
  
  className: string                 # Ingress controller class
                                    # Default: "nginx"
                                    # Options: "nginx", "traefik", "gce", etc.
                                    # CHANGE_ME: match your Ingress controller
  
  annotations:
    cert-manager.io/cluster-issuer: string   # (Optional) cert-manager issuer
                                              # Default: "letsencrypt-prod"
                                              # CHANGE_ME: match your cert issuer
  
  tls:
    enabled: boolean                # Enable TLS/HTTPS
                                    # Default: true (required for production)
    
    issuer: string                  # TLS issuer name
                                    # Default: "letsencrypt-prod"
                                    # Options: "letsencrypt-prod", "self-signed", custom issuer
                                    # CHANGE_ME: match cert-manager configuration
  
  hosts:
    - host: string                  # External hostname
                                    # Default: "ohs.example.org"
                                    # CHANGE_ME: your actual domain
      
      paths:
        - path: string              # URL path
                                    # Examples: "/ehrbase", "/openfhir", "/"
        
          pathType: string          # Path matching type
                                    # Options: "Exact", "Prefix"
                                    # Default: "Prefix"
          
          service: string           # Target service name (Helm release prefix included)
                                    # e.g. "ohs-ehrbase", "ohs-openfhir", "ohs-eos",
                                    # "ohs-keycloak", "ohs-cohort-explorer-backend",
                                    # "ohs-cohort-explorer-frontend"
          port: integer             # Target service port
                                    # ehrbase/openfhir/keycloak 8080, eos 8081,
                                    # cohort-explorer-backend 8090, frontend 80
```

### Example: Ingress Configuration

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  
  tls:
    enabled: true
    issuer: "letsencrypt-prod"
  
  hosts:
    - host: "ohs.hospital.org"
      paths:
        - path: "/ehrbase"
          pathType: "Prefix"
          service: "ohs-ehrbase"
          port: 8080
        - path: "/openfhir"
          pathType: "Prefix"
          service: "ohs-openfhir"
          port: 8080
        - path: "/eos"
          pathType: "Prefix"
          service: "ohs-eos"
          port: 8081
```

---

## RBAC & Security

### `rbac`

Kubernetes RBAC (Role-Based Access Control) configuration.

```yaml
rbac:
  create: boolean                   # Create ServiceAccount, ClusterRole, etc.
                                    # Default: true
  
  name: string                      # ServiceAccount name
                                    # Default: "ohs"
```

### `namespace`

Kubernetes namespace configuration.

```yaml
namespace:
  name: string                      # Namespace name
                                    # Recommended: "ohs" (assumed throughout these docs)
  
  create: boolean                   # Create namespace via Helm
                                    # Default: false
                                    # Set true to auto-create namespace
```

---

## Monitoring & Logging

### `monitoring`

Prometheus monitoring integration (optional, disabled by default).

```yaml
monitoring:
  enabled: boolean                  # Enable monitoring setup
                                    # Default: false (enable if Prometheus is running)
  
  prometheus:
    servicemonitor:
      enabled: boolean              # Create Prometheus ServiceMonitor CRDs
                                    # Default: false
                                    # Requires Prometheus Operator in cluster
```

### `logging`

Logging integration (optional, disabled by default).

```yaml
logging:
  enabled: boolean                  # Enable logging configuration
                                    # Default: false
                                    # (Integration with ELK, Loki, etc.)
```

---

## Sizing by Environment

Scale replicas, storage, and resources with the environment. Rough guidance:

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| `postgres.ehrbase.instances` | 1 | 2 | 3 |
| `postgres.ehrbase.storage` | 10Gi | 20Gi | 100Gi |
| `postgres.eos.storage` | 20Gi | 50Gi | 200Gi |
| `mongodb.openfhir.replicas` | 1 | 2 | 3 |
| app `replicaCount` (ehrbase/openfhir/eos) | 1 | 2 | 3 |
| app resource requests | 100m / 512Mi | 500m / 1Gi | 1000m / 2Gi |
| `monitoring.enabled` | false | false | true |
| `ingress.tls.enabled` | false | true | true |
| `global.podSecurityContext.runAsNonRoot` | false | true | true |

The Docker Desktop profile in `values-local.yaml` is a ready-made development example.

---

## Placeholder Values

The following placeholders should be replaced before production deployment:

| Placeholder | Location | Action |
|-------------|----------|--------|
| `CHANGE_ME` | passwords, endpoints | Replace with actual values |
| `PIN_VERSION` | image tags | Pin specific versions |
| `example.org` | domain | Replace with your domain |
| `your-registry.example.org` | openEHRTool-v2 image | Update to your Docker registry |
| `your_secure_password` | auth/db passwords | Use strong, unique passwords |

---

## Further Reference

- Full values.yaml: See `values.yaml` in repository root
- Subchart documentation: See `charts/*/README.md`
- Deployment guide: See `DEPLOYMENT.md`
- Architecture overview: See `ARCHITECTURE.md`

