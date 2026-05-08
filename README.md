# Open Health Stack (OHS)

A production-grade Kubernetes-native Helm deployment for uniting multiple health data platforms into a unified, interoperable health information system.

## Mission

**"United applications for open data exchange in healthcare"** — Deploy a complete ecosystem of health data tools (EHRbase, openFHIR, Eos/OMOP Bridge, openEHRTool-v2, and more) on Kubernetes using a single Helm umbrella chart, with zero modifications to upstream repositories.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (K8s 1.24+)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           External Access (Kubernetes Ingress)          │    │
│  └──────────┬─────────────────────┬─────────────────────┬──┘    │
│             │                     │                     │       │
│  ┌──────────▼──────┐   ┌──────────▼──────┐   ┌──────────▼───┐   │
│  │    EHRbase      │   │   openFHIR      │   │openEHRTool-v2│   │
│  │  (EHR Storage)  │   │ (FHIR Server)   │   │  (Web Editor)│   │
│  └──────────┬──────┘   └──────────┬──────┘   └───────────┬──┘   │
│             │                     │                      │      │
│  ┌──────────▼───────────────┬─────▼────────────┬─────────▼──┐   │
│  │     PostgreSQL Cluster   │  MongoDB Cluster │ Redis Cache│   │
│  │   (CloudNativePG Op)     │  (Community Op)  │            │   │
│  └──────────────────────────┴──────────────────┴────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Eos (OMOP Bridge) ─► OMOP CDM Database (PostgreSQL)     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Networking (NetworkPolicy) │ RBAC │ Monitoring │        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- Kubernetes 1.24+
- Helm 3.12+
- kubectl configured
- Storage class available
- Ingress controller (Nginx or Traefik)

### Install in 5 Minutes

```bash
# 1. Create namespace and secrets
kubectl create namespace ohs
kubectl create secret generic ohs-credentials \
  --from-literal=ehrbase-user-password=MyPassword123 \
  --from-literal=ehrbase-db-password=MyDbPass456 \
  --from-literal=openfhir-mongo-uri=mongodb://openfhir:MyMongoPass@mongodb-cluster:27017/openfhir \
  --from-literal=eos-db-password=MyEosPass789 \
  -n ohs

# 2. Install Helm chart
helm install ohs . -f values.yaml -n ohs

# 3. Wait for pods
kubectl get pods -n ohs -w

# 4. Access services
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs
# Visit: http://localhost:8080/swagger-ui
```

For detailed instructions, see [GETTING_STARTED.md](GETTING_STARTED.md)

## Components

| Component | Role | Status | Image |
|-----------|------|--------|-------|
| **EHRbase** | EHR Storage (openEHR) | ACTIVE | ehrbase/ehrbase:2.31.0 |
| **openFHIR** | FHIR Server (HL7 FHIR) | ACTIVE | openfhir/openfhir:2.2.1 |
| **Eos** | OMOP Bridge (ETL) | ACTIVE | ghcr.io/SevKohler/Eos:0.0.62 |
| **openEHRTool-v2** | Web Editor & Visualization | ACTIVE (Custom Build) | See [packaging/](packaging/openEHRTool-v2/) |
| **CloudNativePG** | PostgreSQL Operator | ACTIVE | v1.21.0 |
| **MongoDB Operator** | MongoDB Operator | ACTIVE | v0.8.0 |
| **EHRsuction** | Data Export | PLACEHOLDER | — |
| **Kohortenexplorer** | Cohort Query Tool | PLACEHOLDER | — |
| **CSV-to-openEHR** | Bulk Import | PLACEHOLDER | — |
| **BETTER Platform** | External EHR (Charité) | REFERENCE | — |

**Status Legend**: ACTIVE = Deployed | PLACEHOLDER = Disabled by default, ready for implementation | REFERENCE = External system integration

## Documentation

- **[REQUIREMENTS.md](REQUIREMENTS.md)** — Original requirements, constraints, and architectural decisions
- **[GETTING_STARTED.md](GETTING_STARTED.md)** — Quick-start guide, port-forwarding, troubleshooting
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — Full deployment procedures, prerequisites, verification
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — System architecture, data flows, design decisions
- **[VALUES.md](VALUES.md)** — Complete Helm values reference
- **[SECRETS.md](SECRETS.md)** — Secret management best practices (4 methods: kubectl, Sealed Secrets, External Secrets, SOPS)
- **[VERIFICATION.md](VERIFICATION.md)** — Pre/post-deployment verification checklist
- **[NEXT_STEPS.md](NEXT_STEPS.md)** — Deployment checklist, roadmap, and development phases (9-14)

## Security

- **No Secrets in Git**: `.gitignore` excludes all credential files
- **NetworkPolicy**: Default-deny + allow rules for microsegmentation
- **RBAC**: ServiceAccount + ClusterRole with least-privilege
- **Secret Management**: 4 production-grade strategies documented
- **Pod Disruption Budgets**: High-availability configuration
- **Health Checks**: Readiness & liveness probes configured

See [SECRETS.md](SECRETS.md) for comprehensive secret management guide.

## Monitoring & Observability

- **Prometheus Integration**: Optional ServiceMonitor for metrics scraping
- **Pod Metrics**: CPU/memory requests and limits configured
- **Logs**: Pod logs accessible via `kubectl logs`
- **Health Endpoints**: All components expose `/health` endpoints

Enable in `values.yaml`:
```yaml
monitoring:
  enabled: true
  prometheus:
    servicemonitor:
      enabled: true
```

## Key Features

### Umbrella Chart Pattern
Single deployment point with 9 subcharts:
- 5 active (database operators, EHRbase, openFHIR, Eos)
- 4 placeholder components (disabled by default, ready for implementation)

### Database Operators
- **CloudNativePG v1.21.0**: Automated PostgreSQL HA, backups, recovery
- **MongoDB Community Operator v0.8.0**: Automated MongoDB replica sets

### Custom Docker Build
openEHRTool-v2 has no published image:
- Multi-stage Dockerfile (Node 22 frontend + Python 3.11 backend)
- Build instructions in [packaging/openEHRTool-v2/](packaging/openEHRTool-v2/)
- Deploy custom image to your registry

### Configuration Management
- Centralized `values.yaml` with all customizable options
- Placeholder values (CHANGE_ME, PIN_VERSION, example.org) guide configuration
- Component-level toggles enable/disable independently
- Database connection strings, RBAC, ingress all configurable

### No Upstream Modifications
- All upstream repos deployed as-is
- Zero forks or patches
- Easy to track upstream updates
- Governance model for component integration (documented in ARCHITECTURE.md)

## Use Cases

### Development
```yaml
# values.yaml
environment: development
replicas: 1
storage: 5Gi
```

### Staging
```yaml
environment: staging
replicas: 2
storage: 20Gi
```

### Production
```yaml
environment: production
replicas: 3
storage: 100Gi
networkPolicy:
  enabled: true
monitoring:
  enabled: true
```

## Data Integration

OHS unites three major health data paradigms:

1. **OpenEHR** (EHRbase): ISO 13606 standard, archetypes, semantic interoperability
2. **HL7 FHIR** (openFHIR): RESTful APIs, standardized resources, industry adoption
3. **OMOP Common Data Model** (Eos): Structured research data, analytics, CDM ecosystem

All three work together in a single deployment.

## Project Structure

```
ohs-open-health-stack/
├── Chart.yaml                      # Umbrella chart definition
├── values.yaml                     # Master configuration (CHANGE_ME placeholders)
├── .gitignore                      # Excludes secrets, locked charts
├── README.md                       # This file
├── GETTING_STARTED.md              # 5-minute quickstart
├── DEPLOYMENT.md                   # Full deployment guide
├── ARCHITECTURE.md                 # System design & decisions
├── VALUES.md                       # Configuration reference
├── SECRETS.md                      # Secret management guide
├── VERIFICATION.md                 # Testing & validation checklist
│
├── charts/                         # Subcharts
│   ├── cloudnative-pg/             # PostgreSQL operator (v1.21.0)
│   ├── mongodb-operator/           # MongoDB operator (v0.8.0)
│   ├── ehrbase/                    # EHR storage (ehrbase/ehrbase:2.31.0)
│   ├── openfhir/                   # FHIR server (openfhir/openfhir:2.2.1)
│   ├── eos/                        # OMOP Bridge (ghcr.io/SevKohler/Eos:0.0.62)
│   ├── opehrtool-v2/               # Web editor (custom image, see packaging/)
│   ├── ehrsuction/                 # Data export (placeholder)
│   ├── kohortenexplorer/           # Cohort query tool (placeholder)
│   ├── csv-to-openeehr/            # Bulk import (placeholder)
│   └── better-platform/            # External EHR reference
│
├── templates/                      # Root-level templates
│   ├── ingress.yaml                # Kubernetes Ingress (HTTP/HTTPS)
│   ├── configmap.yaml              # Global configuration
│   ├── secrets-reference.yaml      # Secrets creation guide (docs only)
│   ├── rbac.yaml                   # ServiceAccount + ClusterRole
│   ├── networkpolicy.yaml          # Default-deny + allow rules
│   ├── servicemonitor.yaml         # Prometheus metrics (optional)
│   ├── poddisruptionbudget.yaml    # Pod HA policy
│   └── databases/
│       ├── postgres-cluster.yaml   # PostgreSQL cluster (CloudNativePG CRD)
│       └── mongodb-cluster.yaml    # MongoDB cluster (MongoDB Operator CRD)
│
└── packaging/
    └── openEHRTool-v2/
        ├── Dockerfile              # Multi-stage build
        ├── .dockerignore
        └── README.md               # Build instructions
```

## Important Notes

### Secrets
- **Never commit credentials to Git**
- Use one of 4 methods: kubectl, Sealed Secrets, External Secrets Operator, SOPS
- See [SECRETS.md](SECRETS.md) for detailed instructions

### Custom Images
- openEHRTool-v2 must be built locally (see [packaging/openEHRTool-v2/README.md](packaging/openEHRTool-v2/README.md))
- Other components use published Docker images

### Configuration
- Update `values.yaml` with your domain, passwords, replicas
- Search for `CHANGE_ME` placeholders and customize
- Search for `PIN_VERSION` to verify component versions

### Database Persistence
- CloudNativePG and MongoDB use persistent volumes
- Configure storage class in `values.yaml`
- Automated backups can be enabled per operator

## Contributing

### Adding a New Component

1. Create `charts/mynewcomponent/` with:
   - `Chart.yaml`
   - `values.yaml` with `enabled: false` for placeholder
   - `templates/` with Deployment/Service templates
   - `README.md` explaining component role

2. Add to root `values.yaml`:
   ```yaml
   mynewcomponent:
     enabled: false
     # configuration here
   ```

3. Update `ARCHITECTURE.md` with data flow diagram

### Reporting Issues

Please file issues on GitHub with:
- Kubernetes version (`kubectl version`)
- Helm version (`helm version`)
- Component (EHRbase, openFHIR, etc.)
- Error logs (`kubectl logs <pod> -n ohs`)

## References

- **[Kubernetes Docs](https://kubernetes.io/docs/)** — Container orchestration
- **[Helm Docs](https://helm.sh/docs/)** — Package manager
- **[EHRbase Docs](https://docs.ehrbase.org/)** — openEHR EHR storage
- **[openFHIR GitHub](https://github.com/openfhir/openfhir)** — FHIR server
- **[Eos Repository](https://github.com/SevKohler/Eos)** — OMOP Bridge
- **[CloudNativePG Docs](https://cloudnative-pg.io/)** — PostgreSQL operator
- **[MongoDB Operator Docs](https://github.com/mongodb/mongodb-kubernetes-operator)** — MongoDB operator


---

**Last Updated**: 2024
**Kubernetes Version**: 1.24+
**Helm Version**: v3.12+
**Status**: Production-Ready (Phases 1-8 complete)