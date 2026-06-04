# Architecture: Open Health Stack

## Overview

OHS is a Kubernetes-native platform combining:
- **EHRbase** — openEHR EHR storage (ISO 13606)
- **openFHIR** — FHIR R4 API and openEHR bridge
- **Eos** — ETL from openEHR to OMOP CDM for research analytics
- Additional stack components that are staged in the base profile until their deployment path is finalized (EHRsuction, CSV import)

## Component Diagram

```
                    Ingress Controller
                    (Nginx / Traefik)
                           |
          +----------------+----------------+
          |                |                |
     EHRbase           openFHIR            Eos
   (EHR Store)       (FHIR API)       (OMOP Bridge)
          |                |                |
     PostgreSQL        MongoDB         PostgreSQL
     (CloudNativePG)  (Mongo Operator) (same cluster,
                                        eos_omop DB)
```

## Data Flows

### Primary: EHR Ingestion → Normalization

```
External Source / openEHRTool-v2
        |
        v
   EHRbase REST API  -->  PostgreSQL (ehrbase DB)
        |                      |
        |          +-----------+-----------+
        |          |                       |
        v          v                       v
   openFHIR    Transform to            Eos ETL
   Bridge      FHIR resources     Transform to OMOP CDM
        |          |                       |
        v          v                       v
  (reads EHRbase) MongoDB          PostgreSQL (eos_omop DB)
                (FHIR cache)       PERSON, MEASUREMENT,
                                   OBSERVATION, etc.
```

## Helm Chart Structure

```
ohs/
├── Chart.yaml              # Umbrella chart
├── values.yaml             # Master configuration
├── templates/
│   ├── configmap.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── poddisruptionbudget.yaml
│   ├── rbac.yaml
│   ├── secrets-reference.yaml
│   ├── servicemonitor.yaml
│   └── databases/
│       ├── postgres-cluster.yaml   # CloudNativePG Cluster CRD
│       └── mongodb-cluster.yaml    # MongoDB Community CRD
└── charts/
    ├── cloudnative-pg/     # PostgreSQL operator
    ├── mongodb-operator/   # MongoDB operator
    ├── ehrbase/            # EHR store
    ├── openfhir/           # FHIR API
    ├── eos/                # OMOP ETL
     └── [staged charts]     # ehrsuction, csv-to-openeehr, better-platform
```

## Service Ports

| Service | Port | Notes |
|---------|------|-------|
| EHRbase | 8080 | REST + FHIR APIs |
| openFHIR | 8080 | FHIR R4 |
| Eos | **8081** | Spring Boot; `server.port: 8081` in application.yml |
| PostgreSQL (CNPG) | 5432 | Service: `postgres-cluster-rw` (read-write endpoint) |
| MongoDB | 27017 | Service: `mongodb-cluster-svc` |

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Database operators | CloudNativePG + MongoDB Community Operator | HA, automated backups, operator pattern is Kubernetes-native |
| Packaging | Umbrella Helm chart | Single deploy command for entire stack |
| Custom images | openEHRTool-v2 and Cohort Explorer (no upstream images) | All other components have published images; `build-images.sh` handles both |
| Staged subcharts | Base profile keeps some components off until image and config paths are finalized | Preserves a runnable default while the target state remains the full stack |
| Secret management | External to chart (kubectl / Sealed Secrets / ESO) | Secrets never committed to Git |

## Security

- **NetworkPolicy**: Default-deny + per-component allow rules (disabled by default, enable via `networkPolicy.enabled: true`)
- **RBAC**: ServiceAccount + Role per component; mongodb-database SA required in target namespace
- **PodDisruptionBudgets**: Minimum availability during node maintenance
- **Secrets**: Injected from `ohs-credentials` Kubernetes Secret; never stored in chart values
- **TLS**: Terminate at Ingress; enable via `ingress.tls` + cert-manager
