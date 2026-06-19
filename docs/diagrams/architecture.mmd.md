# OHS Architecture Diagrams (Mermaid)

Diagram-as-code companions to the polished [`architecture.drawio`](architecture.drawio)
file. Three views:

1. **Logical / component view** - what the services are and how data moves between them.
2. **Kubernetes deployment view** - how the stack runs in the cluster.
3. **End-to-end data flow** - the path of a single record from ingestion to analytics.

> Renders directly in GitHub, the VS Code Mermaid preview, and most Markdown
> toolchains. For a print-quality figure, export the draw.io version to SVG/PDF.

Shared palette (used across all three diagrams):

| Role | Fill / stroke |
|------|---------------|
| Application service | `#e3effa` / `#3b6ea5` (blue) |
| Stateful data store | `#e6f2e6` / `#4f8a4f` (green) |
| Operator (cluster-wide) | `#fbe9d0` / `#c47f1a` (amber) |
| Ingress / entrypoint | `#fff4cc` / `#c9a227` (gold) |
| Secret / PVC | `#fadbd8` / `#b03a2e` (red) |
| External / client | `#eeeeee` / `#777777` (grey) |

---

## Logical / Component view + primary data flow

```mermaid
flowchart TB
    src["External source /<br/>openEHRTool-v2"]:::ext

    subgraph apps["Application services"]
        ehrbase["EHRbase<br/>openEHR EHR store"]:::app
        openfhir["openFHIR<br/>FHIR R4 bridge"]:::app
        eos["Eos<br/>openEHR → OMOP ETL"]:::app
        cohort["Cohort Explorer<br/>OMOP query UI"]:::app
    end

    subgraph data["Data stores"]
        pg_ehr[("PostgreSQL<br/>ehrbase DB")]:::db
        mongo[("MongoDB<br/>FHIR cache")]:::db
        pg_omop[("PostgreSQL<br/>eos_omop DB<br/>OMOP CDM")]:::db
    end

    analyst["Researcher"]:::ext

    src -->|"REST: create EHR / compositions"| ehrbase
    ehrbase --> pg_ehr
    openfhir -->|"reads compositions"| ehrbase
    openfhir -->|"FHIR resources"| mongo
    eos -->|"reads compositions"| ehrbase
    eos -->|"PERSON, MEASUREMENT,<br/>OBSERVATION ..."| pg_omop
    cohort -->|"OMOP queries"| pg_omop
    analyst -->|"explore cohorts"| cohort

    classDef ext fill:#eeeeee,stroke:#777777,color:#222;
    classDef app fill:#e3effa,stroke:#3b6ea5,color:#222;
    classDef db  fill:#e6f2e6,stroke:#4f8a4f,color:#222;
```

---

## Kubernetes deployment view

```mermaid
flowchart TB
    client["Client / Browser"]:::ext

    subgraph cluster["Kubernetes cluster"]
        direction TB

        subgraph operators["Operator namespaces (cluster-wide)"]
            cnpg["CloudNativePG operator<br/>(ns: cnpg-system)"]:::op
            mongoop["MongoDB Community operator<br/>(ns: mongodb-operator)"]:::op
        end

        ingress{{"Ingress controller<br/>nginx / traefik · TLS via cert-manager"}}:::ingress

        subgraph ns["Namespace: ohs"]
            direction TB

            subgraph applayer["App layer - Deployments + Services"]
                ehrbase["EHRbase :8080"]:::app
                openfhir["openFHIR :8080"]:::app
                eos["Eos :8081"]:::app
                keycloak["Keycloak :8080"]:::app
                ce_fe["Cohort Explorer FE"]:::app
                ce_be["Cohort Explorer BE"]:::app
                tool_fe["openEHRTool FE"]:::app
                tool_be["openEHRTool BE"]:::app
            end

            subgraph datalayer["Data layer - StatefulSets (operator-managed)"]
                pg[("PostgreSQL cluster (CNPG)<br/>ehrbase · eos_omop · numportal")]:::db
                mongo[("MongoDB cluster")]:::db
                redis[("Redis")]:::db
            end

            secret[/"Secret: ohs-credentials"/]:::secret
            pvc[/"PersistentVolumeClaims"/]:::secret
        end
    end

    client --> ingress

    ingress -->|"/ehrbase"| ehrbase
    ingress -->|"/openfhir"| openfhir
    ingress -->|"/eos"| eos
    ingress -->|"/auth"| keycloak
    ingress -->|"/num-portal"| ce_be
    ingress -->|"/cohort-explorer"| ce_fe

    ehrbase -->|":5432"| pg
    eos -->|":5432"| pg
    ce_be -->|":5432"| pg
    openfhir -->|":27017"| mongo
    tool_be --> redis
    tool_fe --> tool_be

    cnpg -.->|manages| pg
    mongoop -.->|manages| mongo
    pg -.-> pvc
    mongo -.-> pvc
    redis -.-> pvc
    secret -.->|env injection| applayer

    classDef ext fill:#eeeeee,stroke:#777777,color:#222;
    classDef app fill:#e3effa,stroke:#3b6ea5,color:#222;
    classDef db  fill:#e6f2e6,stroke:#4f8a4f,color:#222;
    classDef op  fill:#fbe9d0,stroke:#c47f1a,color:#222;
    classDef ingress fill:#fff4cc,stroke:#c9a227,color:#222;
    classDef secret fill:#fadbd8,stroke:#b03a2e,color:#222;

    %% solid arrow  = request / data flow (label = ingress path or port)
    %% dashed arrow = "managed by" / mounts (operator → CRD, store → PVC, Secret → pods)
```

---

## End-to-end data flow (single record)

Traces one clinical record from ingestion through to the analytics UI, crossing
the three data models the stack bridges: **openEHR → FHIR / OMOP CDM → cohort**.

```mermaid
flowchart LR
    user["Clinician / data source"]:::ext

    subgraph capture["1 · Capture (openEHR)"]
        tool["openEHRTool-v2"]:::app
        ehrbase["EHRbase"]:::app
        pg_ehr[("ehrbase DB")]:::db
    end

    subgraph transform["2 · Transform"]
        openfhir["openFHIR<br/>→ FHIR R4"]:::app
        eos["Eos<br/>→ OMOP CDM"]:::app
        mongo[("MongoDB<br/>FHIR cache")]:::db
        pg_omop[("eos_omop DB<br/>OMOP CDM")]:::db
    end

    subgraph analyse["3 · Analyse"]
        ce_be["Cohort Explorer BE"]:::app
        ce_fe["Cohort Explorer FE"]:::app
        analyst["Researcher"]:::ext
    end

    user -->|"enter composition"| tool
    tool -->|"REST: store EHR"| ehrbase
    ehrbase --> pg_ehr

    ehrbase -->|"compositions"| openfhir
    ehrbase -->|"compositions"| eos
    openfhir --> mongo
    eos -->|"PERSON, MEASUREMENT,<br/>OBSERVATION ..."| pg_omop

    pg_omop -->|"OMOP queries"| ce_be
    ce_be --> ce_fe
    ce_fe -->|"cohorts / counts"| analyst

    classDef ext fill:#eeeeee,stroke:#777777,color:#222;
    classDef app fill:#e3effa,stroke:#3b6ea5,color:#222;
    classDef db  fill:#e6f2e6,stroke:#4f8a4f,color:#222;
```
