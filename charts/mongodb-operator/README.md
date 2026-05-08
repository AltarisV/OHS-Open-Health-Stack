# MongoDB Community Operator Subchart

This subchart deploys the MongoDB Community Operator, which manages MongoDB clusters for the Open Health Stack.

## Overview

MongoDB Community Operator is an open-source Kubernetes operator that manages MongoDB replica sets with:
- High availability (automatic failover)
- Persistent storage
- Monitoring integration
- TLS/SSL support
- Version upgrades

## Prerequisites

- Kubernetes 1.21+
- Helm 3.12+
- No prior MongoDB operator installed

## Installation

This is installed as part of the root OHS chart:

```bash
helm install ohs . -f values.yaml
```

## Configuration

All configuration is done via the root `values.yaml`:

```yaml
mongodb-operator:
  enabled: true
  version: "0.8.0"
```

## Customization

### Increase Operator Replicas (HA)

```yaml
# charts/mongodb-operator/values.yaml
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

- MongoDB Operator Docs: https://docs.mongodb.com/kubernetes-operator/master/
- GitHub: https://github.com/mongodb/mongodb-kubernetes-operator
- MongoDB Cluster CRD: See `templates/databases/mongodb-cluster.yaml` in root chart

