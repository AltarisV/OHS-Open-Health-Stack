# Eos Helm Chart

Eos is an ETL tool that transforms EHRbase data into the OMOP Common Data Model (CDM) for research and analytics.

## Overview

This subchart deploys Eos within the Open Health Stack Kubernetes platform.

**Features:**
- Bidirectional EHRbase ↔ OMOP CDM mapping
- OMOP v5.4 compatible schema
- PostgreSQL backend
- Integration with ATHENA vocabularies
- Research data warehouse preparation

## Prerequisites

- Kubernetes 1.24+
- Helm 3.12+
- PostgreSQL cluster (provided by root chart via CloudNativePG operator)
- EHRbase (source data)
- ATHENA vocabularies (must be pre-loaded into database)

## Setup: ATHENA Vocabularies

Eos requires OMOP ATHENA vocabularies to be pre-loaded into the PostgreSQL OMOP schema:

1. **Download vocabularies** from https://athena.ohdsi.org/
   - Requires account registration (free)
   - Download all vocabulary files for your OMOP version

2. **Load the vocabularies** with the repo's helper script, which streams the CSVs
   into the `eos_omop` database via `COPY FROM STDIN` (run from the repo root):
   ```bash
   bash scripts/load-vocab.sh   # place the Athena CSVs in vocab/ first
   ```

3. **Once loaded, set in values.yaml**:
   ```yaml
   config:
     omop:
       athenaVocabulariesPresent: true  # Change from false to true
   ```

## Values

### Configuration

Key values to customize:

```yaml
replicaCount: 1              # Eos typically runs as single instance

image.tag: "latest"          # upstream publishes only 'latest'; pin by digest for production

config:
  database:
    host: postgres-cluster
    name: eos_omop           # PostgreSQL database name
    password: CHANGE_ME      # Inject via Secret
  
  ehrbase:
    enabled: true
    baseUrl: http://ehrbase
    username: ehrbase_user
    password: CHANGE_ME      # Inject via Secret
  
  omop:
    athenaVocabulariesPresent: false  # Set to true when vocabularies loaded
```

## Installation

This subchart is installed as part of the root OHS chart:

```bash
helm install ohs . -f values.yaml
```

## Verification

```bash
# Check pod status
kubectl get pods -l app=eos

# Port-forward to test - Eos listens on 8081, not 8080
kubectl port-forward svc/ohs-eos 8082:8081

# Eos exposes no health endpoint and no actuator. A GET on the POST-only /person
# route returning 405 is what proves the service is up - hence the tcpSocket probe.
curl -o /dev/null -w "%{http_code}
" http://localhost:8082/person   # expect 405

# Check OMOP tables created
kubectl exec -it postgres-cluster-1 -- psql -U postgres -d eos_omop -c "\dt"
```

## API Endpoints

Both conversion routes take either **no body** (convert every EHR) or a JSON body listing
EHR ids. Do not post `{}`: that selects the request-body overload, leaves `Ehrs.ehrIds`
null and fails with `NullPointerException: Cannot read the array length`.

- **`POST http://ohs-eos:8081/person`** - maps EHR subjects to OMOP `person`. Run first.
- **`POST http://ohs-eos:8081/ehr`** - maps compositions to the clinical CDM tables.
  Converts only EHRs that already have a `person` row.

```bash
curl -s -X POST http://localhost:8082/person                       # all EHRs
curl -s -X POST -H "Content-Type: application/json"   -d '{"ehrIds":["<ehr_id>"]}' http://localhost:8082/ehr           # one EHR
```

Athena vocabularies must be loaded first, otherwise `/person` fails with HTTP 500
`TransientPropertyValueException: Person.genderConcept` - see `scripts/load-vocab.sh`.

## OMOP Schema

The OMOP CDM schema includes:
- **Core tables**: PERSON, OBSERVATION_PERIOD, SPECIMEN
- **Clinical event tables**: CONDITION_OCCURRENCE, DRUG_EXPOSURE, PROCEDURE_OCCURRENCE, MEASUREMENT, etc.
- **Standardized vocab tables**: CONCEPT, CONCEPT_RELATIONSHIP, VOCABULARY, etc.
- **Health System tables**: PROVIDER, CARE_SITE, ORGANIZATION, LOCATION, etc.

## Further Reference

- Eos GitHub: https://github.com/SevKohler/Eos
- OHDSI OMOP: https://ohdsi.org/
- ATHENA Vocabularies: https://athena.ohdsi.org/
- OMOP CDM Documentation: https://ohdsi.github.io/CommonDataModel/

