# openFHIR Helm Chart

openFHIR is a FHIRConnect **mapping engine** that converts between openEHR compositions and
FHIR resources in both directions. It is not a FHIR server: it stores no resources and serves
no `/fhir/<Resource>` REST API. Conversion is driven by a FhirConnect model and context plus
the matching operational template, all uploaded to the engine first.

## Overview

This subchart deploys openFHIR within the Open Health Stack Kubernetes platform.

**Features:**
- FHIR STU3, R4 and R4B (the versions `openfhir.config.fhir.versions` enables)
- Two-way transformation: openEHR composition ⇄ FHIR resource
- MongoDB backend for templates, models and contexts
- Integration with EHRbase

## Prerequisites

- Kubernetes 1.24+
- Helm 3.12+
- MongoDB cluster (provided by root chart via MongoDB Community Operator)
- EHRbase (for data synchronization)

## Values

### Configuration

Key values to customize:

```yaml
replicaCount: 2              # Number of pods (HA)
image.tag: "2.2.1"           # openFHIR version (PIN_VERSION)

config:
  fhir:
    versions: ["STU3", "R4", "R4B"]
  
  database:
    mongoUri: "mongodb://..."  # MongoDB connection (inject via Secret)
  
  ehrbase:
    enabled: true
    baseUrl: http://ehrbase
    username: ehrbase_user
    password: CHANGE_ME        # Inject via Secret

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

## Installation

This subchart is installed as part of the root OHS chart:

```bash
helm install ohs . -f values.yaml
```

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | liveness; returns `UP` as plain text |
| `/opt` | GET, POST | list or upload operational templates |
| `/fc/model` | GET, POST | list or upload FhirConnect model mappings |
| `/fc/context` | GET, POST | list or upload FhirConnect contexts |
| `/openfhir/tofhir?templateId=<id>` | POST | composition → FHIR Bundle |
| `/openfhir/toopenehr?templateId=<id>` | POST | FHIR resource → composition |

Conversion needs the template's OPT, model and context loaded first; without them the engine
answers `400` with `Couldn't find a Context Mapper for the inbound request`.

## Further Reference

- GitHub: https://github.com/openfhir/openfhir
- FHIR Specification: https://www.hl7.org/fhir/
- openEHR Standard: https://www.openehr.org/

