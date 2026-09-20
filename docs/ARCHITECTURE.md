# Architecture: Open Health Stack

## Overview

OHS is a Kubernetes-native platform combining:
- **EHRbase** - openEHR EHR storage (ISO 13606)
- **openFHIR** - FHIRConnect mapping engine (openEHR ⇄ FHIR R4). It maps compositions to
  FHIR resources and back; it is not a FHIR REST server and serves no `/fhir/<Resource>` API
- **Eos** - ETL from openEHR to OMOP CDM for research analytics
- Additional stack components that are staged in the base profile until their deployment path is finalized (EHRsuction, CSV import)

## Diagrams

Maintained diagrams live in [`diagrams/`](diagrams/):

- **[`architecture.mmd.md`](diagrams/architecture.mmd.md)** - diagram-as-code (Mermaid),
  rendered inline on GitHub. **This is the maintained source.** Three views: logical /
  component, Kubernetes deployment as the chart ships it, and the end-to-end data flow.
- **[`architecture.drawio`](diagrams/architecture.drawio)** - print-quality, editable in
  [diagrams.net](https://app.diagrams.net) or the draw.io VS Code extension. **Out of
  date** as of 2026-09-03: it still draws two separate PostgreSQL instances (there is
  one, with four databases). Redraw from the Mermaid views before using
  it in a report.

The **logical / component view** (primary data flow) is rendered in the
[project README](../README.md#architecture). The **Kubernetes deployment view** and the
**end-to-end data flow** (openEHR hub; AQL cohorts;
FHIR/OMOP exports) are in [`diagrams/architecture.mmd.md`](diagrams/architecture.mmd.md).

## Helm Chart Structure

```
ohs/
├── Chart.yaml              # Umbrella chart
├── values.yaml             # Master configuration
├── templates/
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── poddisruptionbudget.yaml
│   ├── rbac.yaml
│   ├── secrets-reference.yaml
│   ├── servicemonitor.yaml
│   ├── keycloak-client-reconcile.yaml  # post-upgrade hook, dev profile only
│   ├── ehrsuction/
│   │   ├── cronjob.yaml            # scheduled export
│   │   └── pvc.yaml                # export volume
│   └── databases/
│       ├── postgres-cluster.yaml   # CloudNativePG Cluster CRD
│       ├── mongodb-cluster.yaml    # MongoDB Community CRD
│       ├── numportal-schema-init.yaml  # post-install hook
│       └── numportal-user-seed.yaml    # post-install hook
└── charts/
    ├── cloudnative-pg/           # PostgreSQL operator (informational pin)
    ├── mongodb-operator/         # MongoDB operator (informational pin)
    ├── ehrbase/                  # openEHR store
    ├── openfhir/                 # FHIRConnect mapping engine
    ├── eos/                      # OMOP ETL
    ├── keycloak/                 # identity provider, realm import
    ├── cohort-explorer-backend/  # NUM num-portal API
    ├── cohort-explorer-frontend/ # Angular SPA
    ├── openehrtool-backend/      # openEHRTool API
    ├── openehrtool-frontend/     # openEHRTool UI
    └── openehrtool-redis/        # session/cache store for openEHRTool
```

EHRsuction ships as templates in the umbrella chart rather than as a subchart. There is no
`csv-to-openehr` or `better-platform` chart in this repository.

## Service Ports

| Service | Port | Notes |
|---------|------|-------|
| EHRbase | 8080 | openEHR REST API under the `/ehrbase` context path |
| openFHIR | 8080 | FHIRConnect mapping engine, not a FHIR REST server |
| Eos | **8081** | Spring Boot; `server.port: 8081` in application.yml |
| PostgreSQL (CNPG) | 5432 | Service: `postgres-cluster-rw` (read-write endpoint) |
| MongoDB | 27017 | Service: `mongodb-cluster-svc` |

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Database operators | CloudNativePG + MongoDB Community Operator | HA, automated backups, operator pattern is Kubernetes-native |
| Packaging | Umbrella Helm chart | Single deploy command for entire stack |
| Custom images | openEHRTool-v2 and Cohort Explorer (no upstream images) | All other components have published images; `scripts/build-images.sh` handles both |
| Staged subcharts | Base profile keeps some components off until image and config paths are finalized | Preserves a runnable default while the target state remains the full stack |
| Secret management | External to chart (kubectl / Sealed Secrets / ESO) | Secrets never committed to Git |

## Security

- **NetworkPolicy**: Default-deny + per-component allow rules (disabled by default, enable via `networkPolicy.enabled: true`)
- **RBAC**: ServiceAccount + Role per component; mongodb-database SA required in target namespace
- **PodDisruptionBudgets**: Minimum availability during node maintenance
- **Secrets**: Injected from `ohs-credentials` Kubernetes Secret; never stored in chart values
- **TLS**: Terminate at Ingress; enable via `ingress.tls` + cert-manager
