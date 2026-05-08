# CloudNativePG Operator Subchart

This subchart deploys the CloudNativePG operator, which manages PostgreSQL clusters for the Open Health Stack.

## Overview

CloudNativePG is a Kubernetes operator that manages PostgreSQL clusters with:
- High availability (automatic failover)
- Automated backups
- Point-in-time recovery (PITR)
- Monitoring integration
- Version upgrades

## Prerequisites

- Kubernetes 1.23+
- Helm 3.12+
- No prior PostgreSQL operator installed

## Installation

This is installed as part of the root OHS chart:

```bash
helm install ohs . -f values.yaml
```

## Configuration

All configuration is done via the root `values.yaml`:

```yaml
cloudnative-pg:
  enabled: true
  version: "1.21.0"
  cnpg:
    crds:
      create: true
```

## Customization

### Increase Operator Replicas (HA)

```yaml
# charts/cloudnative-pg/values.yaml
operator:
  replicas: 2  # Run 2 operator replicas for HA
```

### Enable Monitoring

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true  # If Prometheus Operator is installed
```

## Further Reference

- CloudNativePG Docs: https://cloudnative-pg.io/
- GitHub: https://github.com/cloudnative-pg/cloudnative-pg
- PostgreSQL Cluster CRD: See `templates/databases/postgres-cluster.yaml` in root chart

