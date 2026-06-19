# Open Health Stack (OHS)

A Kubernetes-native Helm umbrella chart that deploys a unified health data platform — combining openEHR EHR storage, FHIR interoperability, OMOP CDM analytics, identity management, and export tooling — using Helm with minimal changes to upstream projects.

## Components

| Component                      | Role                                    | Status         | Image                                                                               |
| ------------------------------ | --------------------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| **EHRbase**                    | EHR storage (openEHR / ISO 13606)       | Active         | `ehrbase/ehrbase:2.31.0`                                                            |
| **openFHIR**                   | FHIR R4 server and openEHR bridge       | Active         | `openfhir/openfhir:2.2.1`                                                           |
| **Eos**                        | ETL from openEHR to OMOP CDM            | Active         | `ghcr.io/SevKohler/Eos:latest`                                                      |
| **EHRsuction**                 | openEHR composition export job          | Active         | `localhost:5000/ehrsuction:ohs`                                                     |
| **openEHRTool-v2**             | Web UI for EHR editing (Vue3 + FastAPI) | Active         | `localhost:5000/openehrtool-backend:ohs`, `localhost:5000/openehrtool-frontend:ohs` |
| **Cohort Explorer**            | OMOP CDM query UI                       | Active         | self-built local images                                                             |
| **Keycloak**                   | Identity and access management          | Active         | `quay.io/keycloak/keycloak:24.0`                                                    |
| **CloudNativePG**              | PostgreSQL operator                     | Active         | `1.21.0`                                                                            |
| **MongoDB Community Operator** | MongoDB operator                        | Active         | `0.8.0`                                                                             |
| **CSV-to-openEHR**             | Bulk import from CSV                    | Placeholder    |                                                                                     |
| **BETTER Platform**            | External EHR at Charité                 | Reference only |                                                                                     |

## Architecture

How data flows through the stack — captured as openEHR in EHRbase, then bridged to
FHIR (openFHIR) and transformed to the OMOP CDM (Eos) for analytics:

```mermaid
flowchart TB
    src["External source /<br/>openEHRTool-v2"]:::ext

    subgraph apps["Application services"]
        ehrbase["EHRbase<br/>openEHR EHR store"]:::app
        openfhir["openFHIR<br/>FHIR R4 bridge"]:::app
        eos["Eos<br/>openEHR → OMOP ETL"]:::app
    end

    subgraph data["Data stores"]
        pg_ehr[("PostgreSQL<br/>ehrbase DB")]:::db
        mongo[("MongoDB<br/>FHIR cache")]:::db
        pg_omop[("PostgreSQL<br/>eos_omop DB<br/>OMOP CDM")]:::db
    end

    src -->|"REST: create EHR / compositions"| ehrbase
    ehrbase --> pg_ehr
    openfhir -->|"reads compositions"| ehrbase
    openfhir -->|"FHIR resources"| mongo
    eos -->|"reads compositions"| ehrbase
    eos -->|"PERSON, MEASUREMENT,<br/>OBSERVATION ..."| pg_omop

    classDef ext fill:#eeeeee,stroke:#777777,color:#222;
    classDef app fill:#e3effa,stroke:#3b6ea5,color:#222;
    classDef db  fill:#e6f2e6,stroke:#4f8a4f,color:#222;
```

The Kubernetes deployment view and the full end-to-end data flow are in
[docs/diagrams/](docs/diagrams/) (editable [`architecture.drawio`](docs/diagrams/architecture.drawio)
plus a Mermaid source). See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions.

## Quick Start

See [GETTING_STARTED.md](docs/GETTING_STARTED.md) for the full guide, including operator pre-installation, local image builds, and Docker Desktop setup.

Standard Kubernetes deployment:

```bash
kubectl create namespace ohs --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace ohs name=ohs --overwrite

cp .env.example .env
# Fill in your local or deployment-specific passwords.

bash create-secret.sh

helm upgrade --install ohs . -n ohs -f values.yaml

kubectl get pods -n ohs -w
```

Optional local deployment (Docker Desktop Kubernetes):

```bash
# Build local images required by components without published images.
# Docker Desktop shares the host Docker daemon — no eval step needed.
OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
  bash build-images.sh --registry localhost:5000 --skip-push

bash create-secret.sh

helm upgrade --install ohs . -n ohs -f values.yaml -f values-local.yaml --timeout 15m

kubectl get pods -n ohs -w
```

## Documentation

| File                                     | Contents                                                                   |
| ---------------------------------------- | -------------------------------------------------------------------------- |
| [GETTING_STARTED.md](docs/GETTING_STARTED.md) | Quick start, local setup, image builds, port-forwarding, common operations |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md)           | Full deployment guide and production notes                                 |
| [VERIFICATION.md](docs/VERIFICATION.md)       | Health checks and end-to-end testing workflow                              |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md)       | Component overview, data flows, and design decisions                       |
| [SECRETS.md](docs/SECRETS.md)                 | Secret management with kubectl, Sealed Secrets, ESO, and SOPS              |
| [VALUES.md](docs/VALUES.md)                   | Helm values reference                                                      |
| [NEXT_STEPS.md](docs/NEXT_STEPS.md)           | Roadmap and future phases                                                  |
| [REQUIREMENTS.md](docs/REQUIREMENTS.md)       | Original requirements and architectural constraints                        |

## Project Structure

```text
ohs/
├── Chart.yaml                    # Umbrella chart
├── values.yaml                   # Base configuration
├── values-local.yaml             # Local Docker Desktop overrides
├── create-secret.sh              # Creates required Kubernetes secrets from .env
├── build-images.sh               # Builds self-hosted component images from source
├── charts/                       # Subcharts
├── templates/
│   ├── ingress.yaml
│   ├── rbac.yaml
│   ├── networkpolicy.yaml
│   ├── servicemonitor.yaml
│   ├── poddisruptionbudget.yaml
│   ├── ehrsuction/
│   │   ├── cronjob.yaml          # EHRsuction export CronJob
│   │   └── pvc.yaml              # Persistent export volume
│   └── databases/
│       ├── postgres-cluster.yaml # CloudNativePG Cluster CRD
│       └── mongodb-cluster.yaml  # MongoDB Community CRD
└── docs/
```

## Local Image Builds

openEHRTool-v2, EHRsuction, and Cohort Explorer have no suitable published images and are built from source with `build-images.sh`. Build all at once:

```bash
OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
  bash build-images.sh --registry localhost:5000 --skip-push
```

See [GETTING_STARTED.md](docs/GETTING_STARTED.md) for per-component builds and the `OPENEHRTOOL_BACKEND_HOSTNAME` details.

## EHRsuction Export Job

EHRsuction is deployed as a Kubernetes CronJob.

Run a manual export:

```bash
JOB="ohs-ehrsuction-manual-$(date +%s)"

kubectl create job -n ohs "$JOB" --from=cronjob/ohs-ehrsuction

sleep 3
kubectl logs -n ohs -f job/"$JOB"
```

Exported files are written to the `ohs-ehrsuction-export` PVC.

## Key Notes

* **Operators must be pre-installed**: CloudNativePG and MongoDB Community Operator are required before installing the chart.
* **Secrets are externalized**: copy `.env.example` to `.env`, fill in values, and run `create-secret.sh`.
* **Local Docker Desktop uses `values-local.yaml`**: this profile reduces database replicas, disables selected probes, and uses locally built images.
* **Eos runs on port `8081`**: probes and service `targetPort` are configured accordingly.
* **EHRsuction runs as a CronJob**: exports are written to a persistent volume and can be triggered manually or by schedule.
* **openEHRTool-v2, EHRsuction and Cohort Explorer require local/self-hosted image builds**: use `build-images.sh`.
* **Cohort Explorer and Keycloak are enabled in the local profile**: configure image coordinates, domains, and secrets before deploying on standard Kubernetes.
* **PostgreSQL and MongoDB data are persistent**: verify hook policies, storage classes, backup configuration, and deletion behavior before production use.
