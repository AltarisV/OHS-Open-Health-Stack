# Values Reference: Open Health Stack

This document provides a comprehensive reference for all Helm chart values and their configurations.

## Table of Contents

1. [Global Configuration](#global-configuration)
2. [Database Operators](#database-operators)
3. [PostgreSQL Clusters](#postgresql-clusters)
4. [MongoDB Clusters](#mongodb-clusters)
5. [EHRbase](#ehrbase)
6. [openFHIR](#openfhir)
7. [Eos (OMOP Bridge)](#eos-omop-bridge)
8. [openEHRTool-v2](#opehrtool-v2)
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
    host: string                    # PostgreSQL host/service name
                                    # Default: "postgres-cluster.default.svc.cluster.local"
                                    # CHANGE_ME: update if using external database or different namespace
    
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
    host: "postgres-cluster.default.svc.cluster.local"
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
    mongoUri: string                # MongoDB connection string
                                    # Default: "mongodb://openfhir:PASSWORD@mongodb-cluster:27017/openfhir"
                                    # CHANGE_ME: inject password via Secret
  
  ehrbaseIntegration:
    enabled: boolean                # Enable two-way sync with EHRbase
                                    # Default: true
    
    baseUrl: string                 # EHRbase API endpoint
                                    # Default: "http://ehrbase.default.svc.cluster.local:8080"
                                    # CHANGE_ME: update namespace if different
    
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
                                    # Default: "ghcr.io/SevKohler/Eos"
    tag: string                     # Image tag (PIN_VERSION)
                                    # Current: "0.0.62"
                                    # Check: https://github.com/SevKohler/Eos/releases
    pullPolicy: string
  
  service:
    type: string                    # Default: "ClusterIP"
    port: integer                   # Default: 8080
    targetPort: integer
  
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
    host: string                    # PostgreSQL host
                                    # Default: "postgres-cluster.default.svc.cluster.local"
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
                                    # Default: "http://ehrbase.default.svc.cluster.local:8080"
    
    username: string                # EHRbase username
                                    # Default: "ehrbase_user"
    
    password: string                # EHRbase password
                                    # Default: "CHANGE_ME_SECURE_PASSWORD"
  
  omop:
    athenaVocabulariesPresent: boolean  # Pre-loaded ATHENA vocabularies
                                        # Default: false
                                        # CHANGE_ME to true once vocabularies are in database
    
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

### `opehrtool-v2`

Web-based EHR editor and visualization tool (custom Docker image, disabled by default).

```yaml
opehrtool-v2:
  enabled: boolean                  # Enable deployment
                                    # Default: false (enable only after building custom image)
  
  replicaCount: integer             # Number of pods
                                    # Default: 1
  
  image:
    repository: string              # Docker image repository
                                    # Default: "your-registry.example.org/opehrtool-v2"
                                    # CHANGE_ME: update to your registry
    
    tag: string                     # Image tag (PIN_VERSION)
                                    # Default: "PIN_VERSION"
                                    # CHANGE_ME: build tag (e.g., "0.1.0", "latest")
    
    pullPolicy: string              # Default: "IfNotPresent"
  
  service:
    type: string                    # Default: "ClusterIP"
    port: integer                   # Default: 8080
    targetPort: integer
  
  ingress:
    enabled: boolean                # Default: false (enable when deploying)
    path: string                    # Default: "/opehrtool-v2"
    pathType: string
  
  resources:
    requests:
      cpu: string                   # CHANGE_ME
      memory: string                # CHANGE_ME
    limits:
      cpu: string
      memory: string
  
  frontend:
    port: integer                   # Vue 3 frontend port (internal)
                                    # Default: 3000
  
  backend:
    port: integer                   # FastAPI backend port
                                    # Default: 8000
    
    ehrbaseUrl: string              # EHRbase API endpoint
                                    # Default: "http://ehrbase.default.svc.cluster.local:8080"
    
    ehrbaseUsername: string         # EHRbase credentials
    ehrbasePassword: string         # CHANGE_ME: inject via Secret
  
  redis:
    host: string                    # Redis service host
                                    # Default: "redis.default.svc.cluster.local"
                                    # CHANGE_ME: if using external Redis or different namespace
    
    port: integer                   # Redis port
                                    # Default: 6379
    
    password: string                # Redis password (if protected)
                                    # Default: "" (no password)
                                    # CHANGE_ME: add password if Redis requires auth
```

### Building & Deploying openEHRTool-v2

See `packaging/openEHRTool-v2/README.md` for detailed build instructions.

```bash
# Build custom image
cd packaging/openEHRTool-v2
docker build -t your-registry/opehrtool-v2:0.1.0 .
docker push your-registry/opehrtool-v2:0.1.0

# Update values.yaml
opehrtool-v2:
  enabled: true
  image:
    repository: "your-registry/opehrtool-v2"
    tag: "0.1.0"

# Deploy
helm upgrade ohs . -f values.yaml
```

---

## Placeholder Components

### Disabled-by-Default Subcharts

The following components are defined as placeholders (`enabled: false`) to document architecture. Enable when implementation is ready.

```yaml
ehrsuction:
  enabled: false                    # EHRsuction - Data export tool
                                    # Implementation pending

kohortenexplorer:
  enabled: false                    # Cohort Explorer - OMOP query UI
                                    # Exact tech stack TBD

csv-to-openeehr:
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
          
          service: string           # Target service name
                                    # Options: "ehrbase", "openfhir", "eos", "opehrtool-v2"
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
        - path: "/"
          pathType: "Prefix"
          service: "ehrbase"
        - path: "/openfhir"
          pathType: "Prefix"
          service: "openfhir"
        - path: "/eos"
          pathType: "Prefix"
          service: "eos"
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
                                    # Default: "default"
                                    # CHANGE_ME: use dedicated namespace (e.g., "ohs")
  
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

## Common Configuration Patterns

### Development Environment

```yaml
global:
  environment: "development"

postgres:
  ehrbase:
    instances: 1
    storage: "10Gi"
  eos:
    storage: "20Gi"

mongodb:
  openfhir:
    replicas: 1
    storage: "10Gi"

ehrbase:
  replicaCount: 1
  resources:
    requests:
      cpu: "100m"
      memory: "512Mi"
    limits:
      cpu: "500m"
      memory: "1Gi"

openfhir:
  replicaCount: 1
  resources:
    requests:
      cpu: "100m"
      memory: "512Mi"
    limits:
      cpu: "500m"
      memory: "1Gi"

eos:
  replicaCount: 1
  resources:
    requests:
      cpu: "100m"
      memory: "512Mi"
    limits:
      cpu: "500m"
      memory: "1Gi"
```

### Staging Environment

```yaml
global:
  environment: "staging"

postgres:
  ehrbase:
    instances: 2
    storage: "20Gi"
  eos:
    storage: "50Gi"

ehrbase:
  replicaCount: 2
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"

# (similar for others)
```

### Production Environment

```yaml
global:
  environment: "production"
  podSecurityContext:
    runAsNonRoot: true

postgres:
  ehrbase:
    instances: 3
    storage: "100Gi"
    backupRetention: "90d"
  eos:
    instances: 3
    storage: "200Gi"

mongodb:
  openfhir:
    replicas: 3
    storage: "50Gi"

ehrbase:
  replicaCount: 3
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

# (similar for others)

monitoring:
  enabled: true
  prometheus:
    servicemonitor:
      enabled: true

ingress:
  tls:
    enabled: true
    issuer: "letsencrypt-prod"
```

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

---

**Last Updated**: May 2026  
**Version**: 0.1.0

