# Next Steps & Development Roadmap

This document outlines the next steps for deploying, extending, and improving Open Health Stack (OHS).

---

## Immediate Next Steps (For Deployment)

### 1. Customize Configuration

- [ ] Update `values.yaml` — Replace all `CHANGE_ME` placeholders
  - Domain: `example.org` → your actual domain
  - Namespace: `default` → dedicated namespace (e.g., `ohs`)
  - Credentials: Generate strong passwords for all databases
  - Storage: Adjust `storage` and `storage classes` per environment
  - Replicas: Set based on desired HA level (dev: 1, staging: 2, prod: 3+)
  - Image registry: Update custom image registry paths if needed

### 2. Create Kubernetes Secret

- [ ] Create `ohs-credentials` secret with database passwords
  ```bash
  kubectl create secret generic ohs-credentials \
    --from-literal=ehrbase-user-password=<SECURE_PASSWORD> \
    --from-literal=ehrbase-db-password=<DB_PASSWORD> \
    --from-literal=openfhir-mongo-uri=mongodb://openfhir:<PASSWORD>@mongodb-cluster:27017/openfhir \
    --from-literal=eos-db-password=<EOS_PASSWORD> \
    -n ohs
  ```

### 3. Build & Package openEHRTool-v2 (see Phase 9 below)

### 4. Validate Helm Chart

- [ ] Run `helm lint` to verify YAML syntax
  ```bash
  helm lint . -f values.yaml
  ```

- [ ] Generate templates without deploying
  ```bash
  helm template ohs . -f values.yaml > manifests.yaml
  ```

- [ ] Verify no placeholders remain in rendered output
  ```bash
  ! grep -i "CHANGE_ME\|example.org\|PIN_VERSION" manifests.yaml
  ```

### 5. Deploy to Kubernetes

- [ ] Create namespace
  ```bash
  kubectl create namespace ohs
  ```

- [ ] Install Helm chart
  ```bash
  helm install ohs . -f values.yaml -n ohs
  ```

- [ ] Monitor pod startup (5-15 minutes for database operators)
  ```bash
  kubectl get pods -n ohs -w
  ```

### 6. Verify Deployment

- [ ] Follow [VERIFICATION.md](VERIFICATION.md) checklist
- [ ] Port-forward and test each component
- [ ] Verify databases are initialized
- [ ] Load sample data and perform CRUD operations

---

## Phase 9: openEHRTool-v2 Packaging

**Status**: Pending (no published Docker image exists upstream)

**Objective**: Build and publish a Docker image for [openEHRTool-v2](https://github.com/crs4/openEHRTool-v2) (Vue 3 frontend + FastAPI backend) and integrate it into the OHS Helm deployment.

### Tasks

- [ ] **Clone upstream source**
  ```bash
  git clone https://github.com/crs4/openEHRTool-v2.git packaging/openEHRTool-v2/src
  ```

- [ ] **Write Dockerfile**
  - Multi-stage build: Node.js 22 (Vue 3 build) → Python 3.11-slim (FastAPI runtime)
  - Copy built frontend assets into FastAPI's `static/` directory
  - Run as non-root user
  - Health check on `/health`

- [ ] **Build and push image**
  ```bash
  docker build -t your-registry/opehrtool-v2:0.1.0 packaging/openEHRTool-v2/
  docker push your-registry/opehrtool-v2:0.1.0
  ```

- [ ] **Restore Helm chart**
  - Re-create `charts/opehrtool-v2/` with Deployment, Service, Ingress templates
  - Add Redis dependency (required by FastAPI backend for session caching)
  - Add back to `Chart.yaml` dependencies and `values.yaml`

- [ ] **Configuration**
  - Wire `EHRBASE_URL`, `EHRBASE_USER`, `EHRBASE_PASSWORD` from Secret
  - Wire `REDIS_URL` from Secret or internal Redis
  - Add ingress path `/opehrtool-v2`

### Success Criteria
- [ ] Image builds successfully from upstream source
- [ ] App reachable at `https://ohs.example.org/opehrtool-v2`
- [ ] Connects to EHRbase and Redis correctly

---

## Phase 10: EHRsuction — Data Export Tool

**Status**: Placeholder (architecture and tech stack TBD)

**Objective**: Implement EHRsuction for exporting clinical data out of EHRbase to external systems (BETTER Platform, data lakes, other EHRs).

### Tasks

- [ ] **Define export requirements**
  - Target systems: BETTER Platform, external EHRs, data warehouses
  - Output formats: HL7 v2, FHIR JSON, CDA, native openEHR XML

- [ ] **Select architecture**
  - Option A: Kubernetes CronJob (batch export on schedule)
  - Option B: REST microservice with on-demand export endpoint
  - Option C: Apache Camel route for event-driven export

- [ ] **Implement export engine**
  - EHRbase query client (AQL)
  - Format transformation layer
  - Delivery mechanism (push to target or expose for pull)

- [ ] **Create Helm subchart**
  - Create `charts/ehrsuction/` with appropriate workload template
  - Add to `Chart.yaml` and `values.yaml` (disabled by default)

- [ ] **Testing**
  - Export sample compositions, verify format correctness
  - Load test with large datasets

### Success Criteria
- [ ] Successful round-trip: import data → export → re-import unchanged
- [ ] Audit log for every export operation

---

## Phase 11: Data Mirroring (BETTER Platform Integration)

**Status**: Pending (architecture reserved, implementation TBD)

**Objective**: Implement automated data synchronization from BETTER Platform (external EHR at Charité) to EHRbase.

### Tasks

- [ ] **Design Data Synchronization Strategy**
  - Decide on sync frequency (real-time, batch, scheduled)
  - Choose architecture (Kubernetes Job, CronJob, custom controller, MCP server)
  - Define conflict resolution strategy (last-write-wins, manual review, version control)

- [ ] **Create BETTER Platform Adapter**
  - Develop Kubernetes CronJob or Job template
  - Implement BETTER Platform API client
  - Create EHRbase uploader
  - Handle authentication to both systems

- [ ] **Data Mapping & Transformation**
  - Map BETTER Platform models to openEHR archetypes
  - Implement HL7 v2/FHIR transformation if needed
  - Validate data quality before inserting into EHRbase

- [ ] **Error Handling & Logging**
  - Implement retry logic for failed syncs
  - Log all transformations for audit trail
  - Alert on sync failures

- [ ] **Create Helm Template**
  - Create `charts/better-platform-sync/` subchart
  - Define CronJob/Job configuration in values.yaml
  - Document BETTER Platform API endpoint and credentials

- [ ] **Testing**
  - Test with sample data from BETTER Platform
  - Verify data consistency between BETTER and EHRbase
  - Load test with production data volumes

### Success Criteria
- [ ] Bi-directional data flow (BETTER → EHRbase)
- [ ] 99.9% data transfer success rate
- [ ] < 5 minute sync latency
- [ ] Comprehensive audit logging
- [ ] Documented disaster recovery procedure

---

## Phase 12: Cohort Explorer Implementation

**Status**: Placeholder (implementation unclear, architecture reserved)

**Objective**: Implement Kohortenexplorer (Cohort Explorer) for querying OMOP CDM data.

### Tasks

- [ ] **Evaluate Technology Stack**
  - Research existing open-source cohort tools (N3C, OHDSI apps)
  - Decide between Vue.js (match openEHRTool-v2) or React
  - Plan backend (Python FastAPI, Node.js, Java Spring Boot)

- [ ] **OMOP CDM Schema Verification**
  - Verify ATHENA vocabularies are pre-loaded in database
  - Create sample cohort queries for testing
  - Document OMOP schema assumptions

- [ ] **Frontend Development**
  - Build query builder UI (cohort inclusion/exclusion criteria)
  - Implement results visualization (charts, summary statistics)
  - Add data export capabilities (CSV, FHIR)

- [ ] **Backend Development**
  - Implement OMOP query engine
  - Add result caching for performance
  - Implement RBAC for cohort access control

- [ ] **Create Helm Subchart**
  - Re-create `charts/kohortenexplorer/` subchart
  - Define deployment templates, service, ingress
  - Document configuration options

- [ ] **Testing**
  - Validate cohort queries against reference implementations
  - Load test with realistic dataset sizes
  - Test multi-tenancy if applicable

### Success Criteria
- [ ] Query execution < 30 seconds for typical cohorts
- [ ] Support for complex inclusion/exclusion logic
- [ ] Results reproducible and auditable
- [ ] Integration with EHRbase data (if applicable)

---

## Phase 13: CSV Import Tool Enhancement

**Status**: Placeholder (implementation architecture unclear)

**Objective**: Implement CSV-to-openEHR bulk import functionality.

### Tasks

- [ ] **Design CSV Import Strategy**
  - Decide on file format (single CSV vs. multi-table ZIP)
  - Plan archetype mapping (how CSV columns map to openEHR paths)
  - Design validation workflow (preview, validation errors, apply)

- [ ] **Mapping Configuration**
  - Create CSV-to-archetype mapping templates
  - Implement mapping editor UI (openEHRTool-v2 integration or standalone)
  - Support common use cases (patient demographics, observations, medications)

- [ ] **Import Engine**
  - Implement CSV parser with error handling
  - Create openEHR composition builder from CSV rows
  - Batch EHRbase API calls for performance
  - Implement rollback capability for failed imports

- [ ] **Validation & QA**
  - Validate CSV format before import
  - Check data types and mandatory fields
  - Report validation errors with line numbers
  - Allow preview before final import

- [ ] **Create Helm Components**
  - Re-create `charts/csv-to-openeehr/` subchart
  - Decision: Kubernetes Job (batch), CronJob (scheduled), or web service?
  - Document CSV format and mapping configuration

- [ ] **Testing**
  - Test with various CSV formats and data types
  - Load test with large files (100k+ rows)
  - Verify data integrity in EHRbase post-import

### Success Criteria
- [ ] Support for at least 5 common archetype types
- [ ] Import 1000+ rows in < 2 minutes
- [ ] Clear validation error messages
- [ ] Data auditable (import logs, user tracking)

---

## Phase 14: Production Hardening

**Status**: Pending enhancements

### Tasks

- [ ] **Backup & Disaster Recovery**
  - Implement automated backups for CloudNativePG
  - Implement automated backups for MongoDB
  - Test backup restoration procedure
  - Document RPO (Recovery Point Objective) and RTO (Recovery Time Objective)

- [ ] **TLS/HTTPS Configuration**
  - Set up cert-manager for automatic certificate renewal
  - Configure TLS ingress with Let's Encrypt or internal CA
  - Test HTTPS access to all components

- [ ] **Resource Optimization**
  - Benchmark CPU/memory usage per component
  - Set appropriate requests and limits
  - Configure horizontal pod autoscaling (HPA) if needed
  - Document resource requirements per environment

- [ ] **Secrets Rotation**
  - Implement automated credential rotation (quarterly minimum)
  - Document rotation procedure
  - Test rotation without service interruption

- [ ] **Monitoring Enhancement**
  - Install Prometheus + Grafana (optional)
  - Create dashboards for each component
  - Configure alerting rules for critical metrics
  - Set up log aggregation (ELK, Loki, Splunk)

- [ ] **Access Control Hardening**
  - Review and lock down RBAC permissions
  - Implement pod security policies
  - Configure network policies for all namespaces
  - Implement audit logging for sensitive operations

### Success Criteria
- [ ] All databases backed up daily
- [ ] HTTPS enabled for all external endpoints
- [ ] Monitoring covers 99% of critical paths
- [ ] RTO < 1 hour for disaster recovery

---

## Phase 15: Documentation Enhancements

**Status**: Pending additions

### Tasks

- [ ] **Runbooks**
  - Create runbook for pod failures and recovery
  - Create runbook for database operator issues
  - Create runbook for data corruption scenarios
  - Create runbook for performance degradation

- [ ] **Architecture Decision Records (ADRs)**
  - Document why umbrella chart pattern was chosen
  - Document why CloudNativePG/MongoDB operators selected
  - Document secret management strategy decisions
  - Document networking and RBAC design choices

- [ ] **API Documentation**
  - EHRbase REST API guide (link to official docs)
  - openFHIR REST API guide (link to official docs)
  - Eos ETL API guide (if applicable)
  - Example requests/responses for common operations

- [ ] **Troubleshooting Guides**
  - Database connection issues
  - Pod scheduling/resource issues
  - Network connectivity issues
  - Data consistency issues

- [ ] **Cost Analysis**
  - Document estimated resource consumption
  - Provide cost calculator for cloud platforms (AWS, GCP, Azure)
  - Document cost optimization strategies

### Success Criteria
- [ ] Every error message has corresponding troubleshooting guide
- [ ] New operators can deploy OHS following guides
- [ ] All architectural decisions documented

---

## Progress Tracking

### Current Status: Phase 8 Complete

| Phase | Title | Status | Target Date |
|-------|-------|--------|------------|
| 1 | Repository Foundation | COMPLETE | — |
| 2 | Database Operators | COMPLETE | — |
| 3 | Core FOSS Components | COMPLETE | — |
| 4 | Networking & Security | COMPLETE | — |
| 5 | Production Hardiness | COMPLETE | — |
| 6 | Documentation Polish | COMPLETE | — |
| 7 | Deployment Setup | PENDING | TBD |
| 8 | — | — | — |
| 9 | openEHRTool-v2 Packaging | PENDING | TBD |
| 10 | EHRsuction (Export Tool) | PENDING | TBD |
| 11 | Data Mirroring (BETTER) | PENDING | TBD |
| 12 | Cohort Explorer | PENDING | TBD |
| 13 | CSV Import Tool | PENDING | TBD |
| 14 | Production Hardening | PENDING | TBD |
| 15 | Documentation Enhancements | PENDING | TBD |

---

## Prioritization Guide

### High Priority (Do Next)

1. **Complete Deployment Setup** (Phase 7)
   - Customize configuration
   - Deploy to Kubernetes
   - Verify all components working
   - Load sample data

2. **Production Hardening** (Phase 14)
   - Backups & disaster recovery
   - TLS/HTTPS setup
   - Monitoring & alerting

### Medium Priority (Following Phases)

3. **openEHRTool-v2 Packaging** (Phase 9)
   - Build Docker image from upstream source
   - Restore Helm chart and integration

4. **Data Mirroring** (Phase 11)
   - Integrates BETTER Platform data
   - Supports multi-site deployments

### Low Priority (Nice to Have)

5. **Unimplemented Components** (Phases 10, 12-13)
   - EHRsuction, Cohort Explorer, CSV import
   - Can be added incrementally
   - Community contributions welcome

---

## Contributing

To contribute to OHS:

1. **For Components**: Create feature branch, implement component, submit PR
2. **For Docs**: Submit issues for improvements, create PR with updates
3. **For Bugs**: Report via GitHub issues with reproduction steps
4. **For Features**: Discuss design via GitHub discussions before implementing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines (when created).

---

## Questions?

- **Documentation**: See [GETTING_STARTED.md](GETTING_STARTED.md), [DEPLOYMENT.md](DEPLOYMENT.md), [SECRETS.md](SECRETS.md)
- **Issues**: Create GitHub issue with reproduction steps
- **Discussions**: Use GitHub discussions for questions and ideas
- **Contact**: Use repository issues or discussion forums

---

**Last Updated**: May 2026
**Next Milestone**: Phase 9 (Data Mirroring) kickoff
