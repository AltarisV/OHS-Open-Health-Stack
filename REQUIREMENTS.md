# Project Requirements: Open Health Stack (OHS)

This document captures the original requirements, constraints, and objectives that guided the design and implementation of the Open Health Stack platform.

## Mission Statement

**"The plan is to unite these apps"** — Create the initial low-hanging-fruit implementation for a Helm-based Kubernetes deployment repository that brings together multiple health data tools into a unified, production-ready platform.

## Core Objective

Develop a **production-near architecture prototype** that:
- Unites 9+ health data tools and systems
- Provides a single Kubernetes-native deployment mechanism
- Enables easy integration of new components
- Respects all upstream repositories without modifications
- Serves as a comprehensive reference architecture

---

## Tools & Systems to Integrate

The platform unites the following 9 health data tools and systems:

### Core Components (Primary Focus)

1. **EHRbase** (ehrbase/ehrbase)
   - Role: EHR storage and management
   - Standard: openEHR (ISO 13606)
   - Purpose: Central repository for patient health records

2. **openFHIR / FHIRconnect** (openfhir/openfhir)
   - Role: FHIR server and API gateway
   - Standard: HL7 FHIR (STU3, R4, R4B, R5)
   - Purpose: RESTful access to health data, interoperability layer

3. **Eos / OMOP Bridge** (ghcr.io/SevKohler/Eos)
   - Role: ETL tool for OMOP CDM transformation
   - Standard: OMOP Common Data Model
   - Purpose: Extract EHRbase data to OMOP for analytics and research

### Data Integration & Tools

4. **openEHRTool-v2** (crs4/openEHRTool-v2)
   - Role: Web-based EHR editor and data entry
   - Tech: Vue 3 frontend + FastAPI backend
   - Purpose: User-friendly interface for creating and editing EHR data

5. **EHRsuction**
   - Role: Data export and extraction tool
   - Purpose: Export EHR data in various formats

6. **Cohort Explorer / Kohortenexplorer**
   - Role: OMOP CDM query interface
   - Purpose: Enable cohort identification and research queries on OMOP data

7. **CSV to openEHR**
   - Role: Bulk data import utility
   - Purpose: Import patient data from CSV files into EHRbase

### External Systems (Integration Points)

8. **BETTER Platform** (Charité, Berlin)
   - Role: External EHR system at Charité hospital
   - Purpose: Data source/sink for mirroring and synchronization
   - Status: External VM, not managed by OHS deployment
   - Data Flow: BETTER → EHRbase (bi-directional planned)

9. **Bridgehead**
   - Role: External data sharing infrastructure
   - Purpose: Federated data exchange across institutions
   - Status: External Docker/container service
   - Integration: Planned for future phases

---

## Architectural Constraints

The following 11 constraints shaped the architecture and design decisions:

### 1. No Upstream Modifications
**Constraint**: Do not modify, fork, or patch any upstream repositories.

**Implication**: 
- Deploy all components as-is from official sources
- Use versioned, published Docker images
- Custom deployments must live in OHS repository, not upstream
- Easy upstream tracking and updates

**Implementation**:
- All upstream components referenced by official image tags
- Custom builds (openEHRTool-v2) isolated in `packaging/` directory
- Zero patches applied to upstream source code

### 2. Assume No Public Docker Images
**Constraint**: Assume upstream projects may not have published Docker images.

**Implication**:
- Prepare to build custom Docker images if needed
- Document build process for each component
- Provide multi-stage Dockerfile templates for complex builds

**Implementation**:
- EHRbase, openFHIR, Eos: Use published images (v2.31.0, v2.2.1, v0.0.62)
- openEHRTool-v2: Custom multi-stage Docker build (Node 22 + Python 3.11)
- Build documentation in `packaging/` directory

### 3. Helm-Only Packaging
**Constraint**: Use only Helm charts for Kubernetes deployments. No custom controllers, operators, or imperative scripts.

**Implication**:
- All deployment logic in Helm templates
- Leverage existing Kubernetes operators for stateful services
- No application-specific CRDs developed
- Pure declarative infrastructure-as-code

**Implementation**:
- Umbrella chart pattern (root `Chart.yaml` with 9 subcharts)
- CloudNativePG operator for PostgreSQL
- MongoDB Community Operator for MongoDB
- All templates in YAML with Go templating

### 4. Single Deployment Point
**Constraint**: Users deploy the entire platform with one command.

**Implication**:
- Umbrella chart enables unified deployment
- Components toggleable via values.yaml (not forced)
- Centralized configuration in root values.yaml
- One release name (`ohs`) for the entire stack

**Implementation**:
```bash
helm install ohs . -f values.yaml -n ohs
```

### 5. Component Independence (Toggle-able)
**Constraint**: Enable or disable components independently without breaking the deployment.

**Implication**:
- Each subchart has `enabled: false` default for placeholders
- Core components (EHRbase, openFHIR, Eos) enabled by default
- Placeholder components (EHRsuction, Cohort Explorer, CSV import) disabled
- No hard dependencies between subcharts

**Implementation**:
- All templates use `if .Values.COMPONENT.enabled` conditional rendering
- Placeholder subcharts with zero default configuration
- Optional database operators with independent control

### 6. No Secrets in Git Repository
**Constraint**: Credentials, passwords, and sensitive data must never be committed.

**Implication**:
- `.gitignore` excludes all secret files
- Documentation-only `secrets-reference.yaml` (no actual secrets)
- Users provide secrets via one of 4 production methods
- Clear secret management guide provided

**Implementation**:
- `.gitignore` excludes: `secrets.yaml`, `*-secret.yaml`, `.env`, `.key`, `.pem`
- SECRETS.md documents 4 production methods (kubectl, Sealed Secrets, External Secrets, SOPS)
- All values with credentials marked as CHANGE_ME placeholder

### 7. Database Operators for HA
**Constraint**: Use production-grade database operators instead of manual StatefulSets.

**Implication**:
- CloudNativePG v1.21.0 for PostgreSQL (EHRbase, Eos)
- MongoDB Community Operator v0.8.0 for MongoDB (openFHIR)
- Automated HA, backups, failover built-in
- Reduced operational complexity

**Implementation**:
- `charts/cloudnative-pg/` and `charts/mongodb-operator/` subcharts
- CRD-based cluster definitions (`postgres-cluster.yaml`, `mongodb-cluster.yaml`)
- Configurable replicas, backup retention, storage

### 8. Network & Security First
**Constraint**: Implement production-grade networking and RBAC from the start.

**Implication**:
- NetworkPolicy with default-deny + allow rules
- RBAC ServiceAccount + ClusterRole pattern
- Pod Disruption Budgets for high-availability
- Ingress controller integration for external access

**Implementation**:
- `templates/networkpolicy.yaml`: Default-deny policy + component allow rules
- `templates/rbac.yaml`: ServiceAccount + ClusterRole (placeholder permissions for user customization)
- `templates/poddisruptionbudget.yaml`: Minimum availability guarantees
- `templates/ingress.yaml`: HTTP/HTTPS routing with TLS support

### 9. Placeholder Architecture
**Constraint**: Reserve namespace for future components without requiring implementation.

**Implication**:
- Create disabled subcharts for unclear/future components
- Document integration points and expectations
- Show complete ecosystem vision
- Enable community contributions

**Implementation**:
- EHRsuction (data export): Placeholder subchart with status explanation
- Kohortenexplorer (cohort query): Placeholder subchart
- CSV-to-openEHR (bulk import): Placeholder subchart
- BETTER Platform (external reference): Reference-only documentation

### 10. Clear Separation of Concerns
**Constraint**: Organize code and configuration by component, layer, and concern.

**Implication**:
- Each component in separate subdirectory with own Chart.yaml
- Root-level templates for cross-cutting concerns (ingress, RBAC, monitoring)
- Database configurations isolated (`templates/databases/`)
- Packaging for custom builds isolated (`packaging/`)
- Clear documentation structure

**Implementation**:
```
charts/              # Subcharts per component
templates/           # Root-level shared templates
  databases/         # Database cluster definitions
packaging/           # Custom Docker builds
docs/               # Comprehensive documentation (8 files)
```

### 11. Documentation Over Configuration
**Constraint**: Every architectural decision, configuration option, and deployment step must be documented.

**Implication**:
- Comprehensive README and getting started guide
- Architecture decision records (ADRs)
- Complete values.yaml reference
- Secret management best practices
- Deployment verification checklist
- Troubleshooting guides
- Multiple documentation audiences (operators, developers, architects)

**Implementation**:
- **README.md**: Project overview, quick start, feature highlights
- **GETTING_STARTED.md**: 5-minute deployment guide, common tasks
- **DEPLOYMENT.md**: Prerequisites, installation, verification
- **ARCHITECTURE.md**: System design, data flows, decision log
- **VALUES.md**: Complete configuration reference
- **SECRETS.md**: 4 secret management strategies with examples
- **VERIFICATION.md**: Pre/post-deployment verification checklist
- **NEXT_STEPS.md**: Deployment checklist, roadmap, development phases

---

## Key Assumptions

1. **Kubernetes 1.24+** is available
2. **Helm 3.12+** is installed
3. **Storage class** exists for persistent volumes
4. **Ingress controller** (Nginx or Traefik) is deployed
5. **Docker registry access** available for pulling images
6. **Network connectivity** between all pods (or NetworkPolicy configured)
7. **RBAC** is enabled in the cluster
8. **Database operators** can be installed cluster-wide
9. Users have **kubectl** and **helm** CLI access
10. Users are comfortable with Kubernetes concepts (Deployments, Services, Ingress)

---

## Success Criteria

The implementation is successful if:

1. **All 9 components** can be deployed together via single Helm command
2. **Each component** works independently without hard dependencies
3. **No upstream repositories** were modified or forked
4. **No secrets** appear in Git history or committed files
5. **All configuration** is in `values.yaml` with CHANGE_ME placeholders
6. **All architectural decisions** are documented with rationale
7. **New users** can deploy to Kubernetes in < 5 minutes following GETTING_STARTED.md
8. **Operators** can verify deployment health using VERIFICATION.md checklist
9. **All components** expose health endpoints and support readiness/liveness probes
10. **Production patterns** are applied (HA, backups, monitoring hooks, RBAC, NetworkPolicy)

---

## Out of Scope (Future Phases)

The following are explicitly deferred to future development phases:

1. **Data Mirroring (Phase 9)**: Automated sync from BETTER Platform to EHRbase
2. **Cohort Explorer Implementation (Phase 10)**: Full UI for OMOP CDM querying
3. **CSV Import Tool (Phase 11)**: Complete bulk data import workflow
4. **Production Hardening (Phase 12)**: Advanced monitoring, alerting, cost optimization
5. **Documentation Enhancements (Phase 13)**: Runbooks, ADRs, API guides
6. **Community & Distribution (Phase 14)**: Public Helm registry, use cases, community support
7. **Advanced Features**: Multi-tenancy, real-time sync, federated learning, blockchain audit trails

---

## Implementation Status

**Phases 1-8: COMPLETE**

| Phase | Title | Status |
|-------|-------|--------|
| 1 | Repository Foundation | COMPLETE |
| 2 | Database Operators | COMPLETE |
| 3 | Core FOSS Components | COMPLETE |
| 4 | Custom Packaging | COMPLETE |
| 5 | Placeholder Subcharts | COMPLETE |
| 6 | Networking & Security | COMPLETE |
| 7 | Production Hardiness | COMPLETE |
| 8 | Documentation Polish | COMPLETE |

---

## Version History

- **v0.1.0 (May 2026)**: Initial implementation, Phases 1-8 complete
  - Umbrella chart with 9 subcharts (5 active, 4 placeholders, 1 reference)
  - Database operators (CloudNativePG v1.21.0, MongoDB v0.8.0)
  - Core components: EHRbase v2.31.0, openFHIR v2.2.1, Eos v0.0.62
  - Custom Dockerfile for openEHRTool-v2 (Node 22 + Python 3.11)
  - Production infrastructure: Ingress, RBAC, NetworkPolicy, PDB, monitoring hooks
  - Comprehensive documentation (8 files)

---

## Document References

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — Detailed architectural decisions and design patterns
- **[NEXT_STEPS.md](NEXT_STEPS.md)** — Implementation roadmap and development phases
- **[README.md](README.md)** — Project overview and quick reference
- **[GETTING_STARTED.md](GETTING_STARTED.md)** — Deployment guide and quick start
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — Full deployment procedures

---

**Document Version**: 1.0  
**Last Updated**: May 2026  
**Maintained By**: OHS Project Team
