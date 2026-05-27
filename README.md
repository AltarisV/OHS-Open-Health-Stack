# Open Health Stack (OHS)

A Kubernetes-native Helm umbrella chart that deploys a unified health data platform — combining openEHR EHR storage, FHIR interoperability, and OMOP CDM analytics — using a single `helm install` command with zero modifications to upstream repositories.

## Components

| Component | Role | Status | Image |
|-----------|------|--------|-------|
| **EHRbase** | EHR storage (openEHR / ISO 13606) | Active | ehrbase/ehrbase:2.31.0 |
| **openFHIR** | FHIR R4 server and openEHR bridge | Active | openfhir/openfhir:2.2.1 |
| **Eos** | ETL from openEHR to OMOP CDM | Active | ghcr.io/SevKohler/Eos:latest |
| **openEHRTool-v2** | Web UI for EHR editing (Vue3 + FastAPI) | Disabled — needs custom image |
| **CloudNativePG** | PostgreSQL operator | Active | v1.29.1 |
| **MongoDB Community Operator** | MongoDB operator | Active | v0.13.0 |
| **EHRsuction** | Data export tool | Placeholder |  |
| **Cohort Explorer** | OMOP CDM query UI | Placeholder |  |
| **CSV-to-openEHR** | Bulk import from CSV | Placeholder |  |
| **BETTER Platform** | External EHR at Charité | Reference only |  |

## Quick Start

See [GETTING_STARTED.md](GETTING_STARTED.md) for the full guide including operator pre-installation.

```bash
kubectl create namespace ohs && kubectl label namespace ohs name=ohs
cp .env.example .env        # fill in your passwords
bash create-secret.sh       # Windows: .\create-secret.ps1
helm install ohs . -f values.yaml -n ohs
kubectl get pods -n ohs -w
```

## Documentation

| File | Contents |
|------|----------|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Quick start, port-forwarding, common operations |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Full deployment guide + production notes |
| [VERIFICATION.md](VERIFICATION.md) | Health checks + end-to-end testing |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Component overview, data flows, design decisions |
| [SECRETS.md](SECRETS.md) | Secret management (kubectl, Sealed Secrets, ESO, SOPS) |
| [VALUES.md](VALUES.md) | Complete Helm values reference |
| [NEXT_STEPS.md](NEXT_STEPS.md) | Roadmap and future phases |
| [REQUIREMENTS.md](REQUIREMENTS.md) | Original requirements and architectural constraints |

## Project Structure

```
ohs/
├── Chart.yaml                    # Umbrella chart
├── values.yaml                   # Master configuration
├── charts/                       # Subcharts (one per component)
├── templates/
│   ├── ingress.yaml
│   ├── rbac.yaml
│   ├── networkpolicy.yaml
│   ├── servicemonitor.yaml
│   ├── poddisruptionbudget.yaml
│   └── databases/
│       ├── postgres-cluster.yaml # CloudNativePG Cluster CRD
│       └── mongodb-cluster.yaml  # MongoDB Community CRD
└── packaging/
    └── openEHRTool-v2/           # Custom Docker image build
```

## Key Notes

- **Operators must be pre-installed** (CloudNativePG, MongoDB Community) — see [DEPLOYMENT.md](DEPLOYMENT.md)
- **`ohs-credentials` secret** — copy `.env.example` → `.env`, fill in passwords, run `create-secret.sh` / `create-secret.ps1`
- **Eos runs on port 8081** (not 8080) — probes and service targetPort are configured accordingly
- **`helm upgrade` recreates the PostgreSQL cluster** (hook policy `before-hook-creation`) — all DB data is wiped; change this before production use
- **openEHRTool-v2** has no published Docker image; build it from source in `packaging/openEHRTool-v2/`
