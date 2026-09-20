# Project Requirements: Open Health Stack

This document captures the original requirements and constraints that shaped OHS.

## Mission

Create a single Helm umbrella chart that deploys a unified, production-ready health data
platform in Kubernetes — covering EHR storage, FHIR interoperability, and OMOP CDM analytics.
The catalogue below tracks the in-cluster components plus the external systems they integrate with.

## Components

| # | Component | Role | Status |
|---|-----------|------|--------|
| 1 | EHRbase | openEHR EHR store (ISO 13606) | Active |
| 2 | openFHIR / FHIRconnect | FHIRConnect mapping engine, openEHR ⇄ FHIR (no FHIR REST API) | Active |
| 3 | Eos | ETL from openEHR to OMOP CDM | Active |
| 4 | openEHRTool-v2 | Web UI for EHR editing (Vue3 + FastAPI) | Active |
| 5 | EHRsuction | Data export tool (CronJob) | Active |
| 6 | Cohort Explorer | openEHR / AQL cohort query UI (NUM num-portal) | Active |
| 7 | CSV-to-openEHR | Bulk import from CSV | Placeholder |
| 8 | BETTER Platform | External EHR at Charité | External reference |
| 9 | Bridgehead | Federated data exchange | External reference |

## Architectural Constraints

| # | Constraint | Implementation |
|---|-----------|----------------|
| 1 | No upstream forks | Components run from official published images where they exist; no forked source trees are maintained |
| 2 | Assume images may not exist | `scripts/build-images.sh` clones, applies minimal build-time patches, and builds/pushes images for components without published ones (openEHRTool-v2, EHRsuction, Cohort Explorer) |
| 3 | Helm-only packaging | No custom controllers; CloudNativePG + MongoDB operators for state |
| 4 | Single deploy command | Umbrella chart: `helm install ohs . -f values.yaml -n ohs` |
| 5 | Components independently togglable | All templates wrapped in `if .Values.COMPONENT.enabled` |
| 6 | No secrets in Git | `.gitignore` covers secret files; SECRETS.md documents 4 methods |
| 7 | Production-grade databases | CloudNativePG (PostgreSQL) and MongoDB Community Operator |
| 8 | Network & security first | NetworkPolicy, RBAC, PodDisruptionBudgets in root templates |
| 9 | Placeholder architecture | Disabled subcharts reserve namespace for future components |
| 10 | Separation of concerns | `charts/` per component, `templates/databases/`, `packaging/` for builds |
| 11 | Documentation over configuration | A `docs/` set covering deployment, verification, architecture, secrets, values, and roadmap |

## Success Criteria

1. All in-cluster components deploy together via a single Helm command (external references aside)
2. Each component can be independently enabled/disabled
3. No upstream repositories modified or forked
4. No secrets appear in Git history
5. New users can deploy in under 5 minutes following GETTING_STARTED.md
6. All components carry liveness/readiness probes. Not all expose an HTTP health endpoint:
   Eos has neither `/health` nor an actuator, so its probe is a `tcpSocket` check on 8081.

## Out of Scope (Future Phases)

- Automated data mirroring from BETTER Platform
- CSV import and EHRsuction implementations
- Multi-tenancy and federated learning
- Service mesh integration (Istio/Linkerd)

