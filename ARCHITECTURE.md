# Architecture: Open Health Stack

## Overview

Open Health Stack (OHS) is a Kubernetes-native FOSS platform for federated health data management, combining EHR (Electronic Health Record) storage, FHIR (Fast Healthcare Interoperability Resources) mapping, and OMOP CDM (Observational Medical Outcomes Partnership Common Data Model) analytics in a unified cloud-native deployment.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Open Health Stack (OHS)                            │
│                      Kubernetes Helm Deployment                             │
└─────────────────────────────────────────────────────────────────────────────┘

                         ┌──────────────────────┐
                         │   Ingress Controller │
                         │  (Nginx/Traefik)     │
                         └──────────┬───────────┘
                                    │
                ┌───────────────────┼───────────────────┐
                │                   │                   │
        ┌───────▼──────┐    ┌───────▼──────┐   ┌───────▼──────┐
        │   EHRbase    │    │   openFHIR   │   │     Eos      │
        │  (EHR Store) │    │  (FHIR API)  │   │ (OMOP Bridge)│
        └───────┬──────┘    └───────┬──────┘   └───────┬──────┘
                │                   │                   │
        ┌───────▼──────┐    ┌───────▼──────┐   ┌───────▼──────┐
        │  PostgreSQL  │    │   MongoDB    │   │  PostgreSQL  │
        │   Cluster    │    │   Cluster    │   │   Cluster    │
        │ (CloudNative-│    │  (Community  │   │ (OMOP CDM)   │
        │   PG Oper.) │    │   Operator)  │   │              │
        └──────────────┘    └──────────────┘   └──────────────┘

                         ┌──────────────────┐
                         │ Optional Modules │
                         └──────────────────┘
                                   │
        ┌──────────────┬───────────┼───────────┬──────────────┐
        │              │           │           │              │
    ┌───▼────┐  ┌──────▼──┐  ┌────▼─────┐  ┌─▼────────┐  ┌──▼──────┐
    │openEHR │  │EHRsuction│  │Cohort    │  │CSV→openEHR  │BETTER   │
    │Tool v2 │  │(Export)  │  │Explorer  │  │(Import) │  │Platform │
    │(Editor)│  │          │  │(Query)   │  │        │  │(Ext.Ref)│
    └────────┘  └──────────┘  └──────────┘  └────────┘  └─────────┘

```

## Component Descriptions

### Core Components (Production-Ready)

#### **EHRbase** — Electronic Health Record Store
- **Role**: Central repository for structured health data in openEHR format
- **Technology**: Java/Spring Boot, PostgreSQL
- **Image**: `ehrbase/ehrbase:2.31.0` (published on Docker Hub)
- **API**: REST/FHIR endpoints
- **Data Model**: openEHR (ISO 13606 standard)
- **Key Features**:
  - Multi-tenant capable
  - Temporal data support (version history)
  - FHIR and openEHR APIs
  - Full-text search
  - Security: Basic Auth or OAuth2
- **Kubernetes Deployment**: 2+ replicas for HA
- **Database**: PostgreSQL 15+ (managed by CloudNativePG operator)

#### **openFHIR** — FHIR Server & EHR-FHIR Bridge
- **Role**: Bidirectional mapping between openEHR (EHRbase) and FHIR resources
- **Technology**: Java/Spring Boot, MongoDB
- **Image**: `openfhir/openfhir:2.2.1` (published on Docker Hub/GHCR)
- **API**: FHIR STU3, R4, R4B, R5 endpoints
- **Key Features**:
  - Transforms EHRbase data to/from FHIR resources
  - Supports multiple FHIR versions
  - RESTful API
- **Kubernetes Deployment**: 2+ replicas for HA
- **Database**: MongoDB (managed by MongoDB Community Operator)

#### **Eos** — OMOP CDM Bridge
- **Role**: Extract-Transform-Load (ETL) from EHRbase to OMOP Common Data Model for research/analytics
- **Technology**: Java/Spring Boot, PostgreSQL
- **Image**: `ghcr.io/SevKohler/Eos:0.0.62` (published on GitHub Container Registry)
- **Key Features**:
  - OMOP CDM v5.4+ compatible schema
  - Maps EHRbase clinical data to OMOP standard tables
  - Integrates ATHENA vocabularies
  - Research data lake preparation
- **Kubernetes Deployment**: 1+ replicas (can run in batch mode)
- **Database**: PostgreSQL (same cluster as EHRbase, separate schema)

### Extended Components (Placeholder/Disabled)

#### **openEHRTool-v2** — EHR Data Editor & Visualization
- **Role**: Web-based interface for creating/editing EHR data
- **Technology**: Vue 3 (frontend), FastAPI (backend), Redis (cache)
- **Image**: Custom build (no published image; see `packaging/openEHRTool-v2/`)
- **Status**: Disabled by default; enable after building custom Docker image
- **Data Flow**: Editor → FastAPI backend → EHRbase REST API

#### **EHRsuction** — Data Export Tool
- **Role**: Export clinical data from EHRbase to external formats
- **Status**: Placeholder; implementation tech TBD
- **Potential Use Cases**: Extract for external systems, compliance reporting, backup

#### **Cohort Explorer** — OMOP Query & Analytics UI
- **Role**: Query OMOP CDM data extracted by Eos
- **Status**: Placeholder; exact tech stack TBD
- **Potential Integration**: Reads from Eos PostgreSQL schema, provides research data discovery interface

#### **CSV to openEHR** — Bulk Data Import
- **Role**: Batch load CSV data into EHRbase
- **Status**: Placeholder; implementation strategy TBD
- **Potential Implementation**: Kubernetes CronJob, dedicated microservice, or Apache Camel route

#### **BETTER Platform** — External Reference
- **Role**: External EHR system running on Charité VM
- **Status**: External (not managed by this Helm deployment)
- **Future Integration**: Data mirroring from BETTER → EHRbase (Phase N)
- **Current Integration**: Documented endpoint reference only

### Infrastructure Components

#### **Database Operators**

**CloudNativePG** (PostgreSQL)
- Manages PostgreSQL clusters for EHRbase and Eos
- Features: HA, automated backups, PITR, monitoring
- Version: 1.21.0+

**MongoDB Community Operator** (MongoDB)
- Manages MongoDB replica sets for openFHIR
- Features: HA, automated failover, monitoring
- Version: 0.8.0+

#### **Kubernetes Ingress**
- Routes external requests to internal services
- Supports TLS termination
- Default example: Nginx Ingress Controller
- Alternatives: Traefik, HAProxy, cloud-native ingress (AWS ALB, GCP Load Balancer)

#### **Secrets & Configuration**
- **ConfigMaps**: Shared configuration (endpoints, FHIR versions, OMOP settings)
- **Secrets**: Sensitive data (passwords, tokens, API keys)
  - Best practice: Inject via Kubernetes Secrets, Sealed Secrets, or External Secrets Operator
  - Never commit to Git

## Data Flows

### Primary Flow: Patient Data Ingestion & Normalization

```
CSV/External Source
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  CSV to openEHR (optional, planned Phase N)         │
│  Transforms CSV rows to openEHR composition format  │
└─────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│  EHRbase REST API                                   │
│  POST /ehr/{ehrId}/compositions                     │
│  Store structured EHR data in openEHR format        │
└─────────────────────────────────────────────────────┘
       │ (Clinical data: patient demographics, vitals, diagnoses, lab results)
       ▼
   PostgreSQL Cluster (EHRbase schema)
       │
       │ ◄─── Dual read path
       │
       ├──────────────────────────────────────────────┐
       │                                               │
       ▼                                               ▼
┌──────────────────────────┐                ┌──────────────────────────┐
│  openFHIR Bridge         │                │  Eos (OMOP ETL)          │
│  Transform to FHIR/JSON  │                │  Transform to OMOP CDM   │
└──────────────────────────┘                └──────────────────────────┘
       │                                               │
       ▼                                               ▼
   MongoDB (FHIR resources)                   PostgreSQL Cluster
   (openFHIR schema)                          (Eos OMOP schema)
       │                                               │
       │                                               ▼
       │                                    Standardized OMOP tables:
       │                                    - PERSON, OBSERVATION_PERIOD
       │                                    - CONDITION_OCCURRENCE
       │                                    - DRUG_EXPOSURE
       │                                    - PROCEDURE_OCCURRENCE
       │                                    - MEASUREMENT
       │                                    (+ 50+ more tables)
       │                                               │
       └──────────────┬──────────────────────────────┘
                      │
                      ▼
           ┌───────────────────────────────┐
           │  Cohort Explorer (optional)   │
           │  Query & analytics on OMOP    │
           │  Patient cohort discovery     │
           └───────────────────────────────┘
```

### Secondary Flow: Editor & Data Refinement

```
┌────────────────────────────────────────┐
│  openEHRTool-v2 (optional, disabled)   │
│  Vue 3 web UI for EHR composition      │
│  editing & refinement                  │
└────────────────────────────────────────┘
       │
       │ (HTTP REST)
       │
       ▼
┌────────────────────────────────────────┐
│  EHRbase REST API                      │
│  GET /ehr/{ehrId}/compositions         │
│  POST /ehr/{ehrId}/compositions/{id}   │
└────────────────────────────────────────┘
       │
       ▼
   PostgreSQL (EHRbase schema)
```

### Tertiary Flow: Data Export (Planned)

```
PostgreSQL (EHRbase schema)
       │
       ▼
┌────────────────────────────────────────┐
│  EHRsuction (optional, disabled)       │
│  Extract to HL7 v2, JSON, or XML       │
└────────────────────────────────────────┘
       │
       ▼
External Systems (BETTER Platform, EHR federation)
```

## Deployment Architecture

### Kubernetes Cluster Requirements

- **Version**: 1.24+
- **Nodes**: 3+ for HA (production recommendation)
- **Storage**: Persistent volumes (10+ GiB for EHRbase, 50+ GiB for Eos OMOP)
- **Ingress Controller**: Nginx, Traefik, or cloud-native option
- **Optional**: Cert-manager for TLS, Prometheus for monitoring

### Helm Chart Structure

```
ohs/
├── Chart.yaml                 # Root umbrella chart metadata
├── values.yaml               # Master values (global config + per-component defaults)
├── templates/
│   ├── configmap.yaml        # Shared ConfigMaps (endpoints, FHIR versions)
│   ├── secrets.yaml          # Secret references (credentials, tokens)
│   ├── ingress.yaml          # Ingress routing rules
│   ├── serviceaccount.yaml   # RBAC ServiceAccount
│   ├── clusterrole.yaml      # RBAC ClusterRole (for operators)
│   ├── networkpolicy.yaml    # Network security policies (optional)
│   └── databases/
│       ├── postgres-cluster.yaml   # CloudNativePG Cluster CRD
│       └── mongodb-cluster.yaml    # MongoDB Cluster CRD
├── charts/
│   ├── cloudnative-pg/       # PostgreSQL operator subchart
│   ├── mongodb-operator/     # MongoDB operator subchart
│   ├── ehrbase/              # EHRbase deployment subchart
│   ├── openfhir/             # openFHIR deployment subchart
│   ├── eos/                  # Eos (OMOP Bridge) subchart
│   ├── opehrtool-v2/         # openEHRTool-v2 subchart (custom image)
│   ├── ehrsuction/           # EHRsuction placeholder subchart
│   ├── kohortenexplorer/     # Cohort Explorer placeholder subchart
│   ├── csv-to-openeehr/      # CSV import placeholder subchart
│   └── better-platform/      # BETTER Platform reference subchart
└── packaging/
    └── openEHRTool-v2/       # Custom Docker image build
        ├── Dockerfile
        ├── .dockerignore
        └── README.md

```

## Security Considerations

### Network Security
- **NetworkPolicy**: Pod-to-pod communication restricted by default
- **Ingress TLS**: All external traffic encrypted with HTTPS
- **Service-to-service**: mTLS recommended for production (via service mesh or cert-manager)

### Data Security
- **Encryption at rest**: Database encryption (PostgreSQL pgcrypto, MongoDB encryption)
- **Encryption in transit**: TLS for all APIs
- **Access control**: RBAC, pod security policies, network policies

### Secret Management
- **Never commit secrets** to Git
- **Injection methods** (in order of recommendation for production):
  1. Kubernetes Secrets (basic, native)
  2. Sealed Secrets (encrypted secrets in Git)
  3. External Secrets Operator (integrates with HashiCorp Vault, AWS Secrets Manager, etc.)
  4. SOPS (encrypted YAML files)

### Compliance
- **Audit logging**: Kubernetes API audit, application logs
- **Data retention**: Database backup policies aligned with GDPR/legal requirements
- **Anonymization**: Patient identifiers separated from clinical data (optional OMOP de-identification)

## Scalability & Performance

### Horizontal Scaling
- **EHRbase**: StatefulSet or Deployment with load balancing
- **openFHIR**: Multiple replicas behind service load balancer
- **Eos**: Batch jobs via CronJob or on-demand Job

### Vertical Scaling
- Database resource limits: Configurable in values.yaml
- Application resource requests/limits: Per-subchart configuration

### Performance Optimization
- **Caching**: Redis for openEHRTool-v2 backend
- **Database indexing**: EHRbase and Eos schema indices pre-configured
- **Connection pooling**: Application-level (handled by Spring Boot HikariCP)

## Monitoring & Observability

### Logging
- **Application logs**: stdout/stderr captured by Kubernetes
- **Integration**: ELK, Loki, or cloud-native logging (AWS CloudWatch, GCP Logs)
- **Log levels**: Configurable per component

### Metrics
- **Prometheus**: Optional ServiceMonitor CRDs defined (disabled by default)
- **Metrics collected**: JVM (EHRbase, Eos), request latency, database connections
- **Visualization**: Grafana dashboards (optional)

### Health Checks
- **Liveness probes**: Restart unhealthy containers (`/health` endpoint)
- **Readiness probes**: Remove from service if not ready
- **Startup probes**: Wait for application initialization (optional)

## Disaster Recovery & Backup

### Database Backups
- **CloudNativePG**: Automated WAL archiving, point-in-time recovery (PITR)
- **MongoDB**: Regular snapshots, retention policy configurable
- **Backup storage**: External S3 bucket or cluster PVC

### High Availability
- **Multi-replica deployments**: All core components support 2+ replicas
- **Database HA**: Operator-managed failover
- **Pod Disruption Budgets**: Ensure minimum replicas during maintenance

## Decision Log

### 1. Umbrella Chart Pattern
**Decision**: Single root `ohs` chart with subcharts per component.
**Rationale**: Simplified deployment; users deploy entire platform at once.
**Alternative considered**: Individual charts per component (enables à la carte deployment; deferred to Phase N).

### 2. Database Operators vs. Bitnami/Helm Charts
**Decision**: CloudNativePG and MongoDB Community Operators.
**Rationale**: Production-grade HA, automated backups, monitoring; operator pattern is Kubernetes native.
**Alternative considered**: Bitnami Helm charts (easier initial setup, less control over HA).

### 3. Image Publishing Strategy
**Decision**: Reference pre-built images only; custom Dockerfile in `packaging/` for openEHRTool-v2.
**Rationale**: Helm must not build images (architectural requirement); custom image provided as optional extension.
**Alternative considered**: Include image build in Helm post-install hooks (adds complexity, breaks pure Helm pattern).

### 4. External Dependencies (BETTER, Bridgehead)
**Decision**: Document as external references; ConfigMaps/Secrets for connection details.
**Rationale**: Align with user's architecture (BETTER/Bridgehead not managed by OHS); data mirroring deferred to Phase N.
**Alternative considered**: Create placeholder CronJob/Job for mirroring now (premature; unclear specification).

### 5. Placeholder Subcharts
**Decision**: Create disabled subcharts for EHRsuction, Cohort Explorer, CSV→openEHR, BETTER Platform.
**Rationale**: Reserve namespace and document integration points for future components.
**Alternative considered**: Omit entirely (simpler initial codebase, but no architectural roadmap visible).

## Next Steps & Future Phases

- **Phase N**: CI/CD pipeline for openEHRTool-v2 image building
- **Phase N+1**: Data mirroring from BETTER Platform to EHRbase
- **Phase N+2**: Cohort Explorer implementation (Shiny/Streamlit + OMOP query layer)
- **Phase N+3**: Service mesh integration (Istio/Linkerd) for advanced traffic management
- **Phase N+4**: Advanced monitoring with Prometheus + Grafana
- **Phase N+5**: Multi-cluster federation (Kubernetes multi-cluster setup)

---

**Last Updated**: May 2026  
**Version**: 0.1.0 (MVP)  
**Status**: Production-Ready

