# Project Requirements: Open Health Stack

This document captures the original requirements and constraints that shaped OHS.

## Mission

Create a single Helm umbrella chart that deploys 9 health data tools together in Kubernetes, providing a unified, production-ready platform for EHR storage, FHIR interoperability, and OMOP CDM analytics.

## Components

| # | Component | Role | Status |
|---|-----------|------|--------|
| 1 | EHRbase | openEHR EHR store (ISO 13606) | Active |
| 2 | openFHIR / FHIRconnect | FHIR R4 API & openEHR bridge | Active |
| 3 | Eos | ETL from openEHR to OMOP CDM | Active |
| 4 | openEHRTool-v2 | Web UI for EHR editing (Vue3 + FastAPI) | Disabled — needs custom image |
| 5 | EHRsuction | Data export tool | Placeholder |
| 6 | Cohort Explorer | OMOP CDM query UI | Required component |
| 7 | CSV-to-openEHR | Bulk import from CSV | Placeholder |
| 8 | BETTER Platform | External EHR at Charité | External reference |
| 9 | Bridgehead | Federated data exchange | External reference |

## Architectural Constraints

| # | Constraint | Implementation |
|---|-----------|----------------|
| 1 | No upstream modifications | All components deployed from official published images |
| 2 | Assume images may not exist | Custom `Dockerfile` in `packaging/` for openEHRTool-v2 |
| 3 | Helm-only packaging | No custom controllers; CloudNativePG + MongoDB operators for state |
| 4 | Single deploy command | Umbrella chart: `helm install ohs . -f values.yaml -n ohs` |
| 5 | Components independently togglable | All templates wrapped in `if .Values.COMPONENT.enabled` |
| 6 | No secrets in Git | `.gitignore` covers secret files; SECRETS.md documents 4 methods |
| 7 | Production-grade databases | CloudNativePG (PostgreSQL) and MongoDB Community Operator |
| 8 | Network & security first | NetworkPolicy, RBAC, PodDisruptionBudgets in root templates |
| 9 | Placeholder architecture | Disabled subcharts reserve namespace for future components |
| 10 | Separation of concerns | `charts/` per component, `templates/databases/`, `packaging/` for builds |
| 11 | Documentation over configuration | 8 documentation files covering all aspects of deployment and operation |

## Success Criteria

1. All 9 components deploy together via a single Helm command
2. Each component can be independently enabled/disabled
3. No upstream repositories modified or forked
4. No secrets appear in Git history
5. New users can deploy in under 5 minutes following GETTING_STARTED.md
6. All components expose health endpoints with liveness/readiness probes

## Out of Scope (Future Phases)

- Automated data mirroring from BETTER Platform
- CSV import and EHRsuction implementations
- Multi-tenancy and federated learning
- Service mesh integration (Istio/Linkerd)

See [NEXT_STEPS.md](NEXT_STEPS.md) for the full roadmap.
