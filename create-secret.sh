#!/usr/bin/env bash
# Creates the ohs-credentials Kubernetes secret from a .env file.
# Usage: cp .env.example .env && # fill in values && bash create-secret.sh

set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Error: .env file not found. Copy .env.example and fill in your values." >&2
  exit 1
fi

set -a; source .env; set +a

kubectl create secret generic ohs-credentials -n ohs \
  --from-literal=ehrbase-user-password="${EHRBASE_USER_PASSWORD}" \
  --from-literal=ehrbase-db-password="${EHRBASE_DB_PASSWORD}" \
  --from-literal=ehrbase-admin-password="${EHRBASE_ADMIN_PASSWORD}" \
  --from-literal=eos-db-password="${EOS_DB_PASSWORD}" \
  --from-literal=redis-password="${REDIS_PASSWORD}" \
  --from-literal=openfhir-mongo-uri="mongodb://openfhir:${OPENFHIR_MONGO_PASSWORD}@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir?replicaSet=mongodb-cluster" \
  --from-literal=keycloak-admin-password="${KEYCLOAK_ADMIN_PASSWORD}" \
  --from-literal=numportal-keycloak-secret="${NUMPORTAL_KEYCLOAK_SECRET}" \
  --from-literal=numportal-pseudonymity-secret="${NUMPORTAL_PSEUDONYMITY_SECRET}" \
  --from-literal=openehrtool-jwt-secret="${OPENEHRTOOL_JWT_SECRET:-change-me-in-production}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-keycloak-user-secret -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="keycloak" \
  --from-literal=password="${KEYCLOAK_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-numportal-user-secret -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="numportal" \
  --from-literal=password="${NUMPORTAL_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied in namespace 'ohs'."
