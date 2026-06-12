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
| **CloudNativePG**              | PostgreSQL operator                     | Active         | `v1.29.1`                                                                           |
| **MongoDB Community Operator** | MongoDB operator                        | Active         | `v0.13.0`                                                                           |
| **CSV-to-openEHR**             | Bulk import from CSV                    | Placeholder    |                                                                                     |
| **BETTER Platform**            | External EHR at Charité                 | Reference only |                                                                                     |

## Quick Start

See [GETTING_STARTED.md](GETTING_STARTED.md) for the full guide, including operator pre-installation, local image builds, and Docker Desktop setup.

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
| [GETTING_STARTED.md](GETTING_STARTED.md) | Quick start, local setup, image builds, port-forwarding, common operations |
| [DEPLOYMENT.md](DEPLOYMENT.md)           | Full deployment guide and production notes                                 |
| [VERIFICATION.md](VERIFICATION.md)       | Health checks and end-to-end testing workflow                              |
| [ARCHITECTURE.md](ARCHITECTURE.md)       | Component overview, data flows, and design decisions                       |
| [SECRETS.md](SECRETS.md)                 | Secret management with kubectl, Sealed Secrets, ESO, and SOPS              |
| [VALUES.md](VALUES.md)                   | Helm values reference                                                      |
| [NEXT_STEPS.md](NEXT_STEPS.md)           | Roadmap and future phases                                                  |
| [REQUIREMENTS.md](REQUIREMENTS.md)       | Original requirements and architectural constraints                        |

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

Some components are built from upstream source repositories because no suitable published deployment image is available or because the image must be configured for this stack.

```bash
# Docker Desktop shares the host Docker daemon — no eval step needed.

# Build all supported local images.
OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
  bash build-images.sh --registry localhost:5000 --skip-push

# Build individual components.
bash build-images.sh --registry localhost:5000 --component ehrsuction --skip-push
bash build-images.sh --registry localhost:5000 --component cohort-explorer-backend --skip-push
bash build-images.sh --registry localhost:5000 --component cohort-explorer-frontend --skip-push
bash build-images.sh --registry localhost:5000 --component openehrtool-backend --skip-push

# OPENEHRTOOL_BACKEND_HOSTNAME is baked into the Vue bundle at build time.
# Use 'localhost' for local access via kubectl port-forward.
OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
  bash build-images.sh --registry localhost:5000 --component openehrtool-frontend --skip-push
```

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
