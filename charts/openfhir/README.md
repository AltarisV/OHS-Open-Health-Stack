# openFHIR Helm Chart

openFHIR is a FHIR server that provides bidirectional mapping between openEHR (EHRbase) and FHIR resources.

## Overview

This subchart deploys openFHIR within the Open Health Stack Kubernetes platform.

**Features:**
- FHIR STU3, R4, R4B, R5 support
- Two-way transformation: EHR ↔ FHIR
- MongoDB backend
- RESTful FHIR API
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

- **FHIR Base**: http://ohs-openfhir:8080/fhir/
- **Patient Resource**: http://ohs-openfhir:8080/fhir/Patient
- **Health Check**: http://ohs-openfhir:8080/health

## Further Reference

- GitHub: https://github.com/openfhir/openfhir
- FHIR Specification: https://www.hl7.org/fhir/
- openEHR Standard: https://www.openehr.org/

