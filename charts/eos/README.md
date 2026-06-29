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

image.tag: "0.0.62"          # Eos version (PIN_VERSION)

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

# Port-forward to test
kubectl port-forward svc/ohs-eos 8080:8080

# Test health endpoint
curl -s http://localhost:8080/health | jq .

# Check OMOP tables created
kubectl exec -it postgres-cluster-0 -- psql -U eos -d eos_omop -c "\dt eos_omop.*"
```

## API Endpoints

- **Health Check**: http://ohs-eos:8080/health
- **ETL Status**: http://ohs-eos:8080/api/eos/status (if available)

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

