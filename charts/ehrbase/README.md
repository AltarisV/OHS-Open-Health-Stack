# EHRbase Helm Chart

EHRbase is an open-source Electronic Health Record (EHR) storage system implementing the openEHR standard.

## Overview

This subchart deploys EHRbase within the Open Health Stack Kubernetes platform.

**Features:**
- openEHR REST API (FHIR and openEHR endpoints)
- PostgreSQL backend (multi-tenant capable)
- Basic Auth or OAuth2 support
- High availability (multiple replicas)
- Full-text search capabilities

## Prerequisites

- Kubernetes 1.24+
- Helm 3.12+
- PostgreSQL cluster (provided by root chart via CloudNativePG operator)
- Ingress controller (Nginx, Traefik, etc.)

## Values

### Configuration

Key values to customize:

```yaml
replicaCount: 2              # Number of pods (HA)
image.tag: "2.31.0"          # EHRbase version (PIN_VERSION)

config:
  auth:
    username: ehrbase_user
    password: CHANGE_ME_SECURE_PASSWORD  # Inject via Secret
    type: BASIC              # BASIC or OAUTH2
  
  database:
    host: postgres-cluster   # PostgreSQL service name
    name: ehrbase            # Database name
    password: CHANGE_ME      # Database password (inject via Secret)
  
  jvm:
    maxHeapSize: "2g"        # Maximum JVM memory
    minHeapSize: "512m"

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

## Installation

This subchart is installed as part of the root OHS chart:

```bash
helm install ohs . -f values.yaml
```

## Verification

```bash
# Check pod status
kubectl get pods -l app=ehrbase

# Port-forward to test
kubectl port-forward svc/ohs-ehrbase 8080:8080

# Test health endpoint
curl -s http://localhost:8080/health | jq .
```

## API Documentation

- **REST API**: http://ohs-ehrbase:8080/rest/openehr/v1/
- **FHIR API**: http://ohs-ehrbase:8080/fhir/
- **Health check**: http://ohs-ehrbase:8080/health

## Further Reference

- EHRbase Docs: https://www.ehrbase.org/
- GitHub: https://github.com/ehrbase/ehrbase
- openEHR Standard: https://www.openehr.org/

