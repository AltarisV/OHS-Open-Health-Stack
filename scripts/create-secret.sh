#!/usr/bin/env bash
# Creates the ohs-credentials Kubernetes secret and PostgreSQL basic-auth secrets from a .env file.
# Usage:
#   cp .env.example .env
#   # fill in values
#   kubectl create namespace ohs --dry-run=client -o yaml | kubectl apply -f -
#   bash create-secret.sh

set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Error: .env file not found. Copy .env.example and fill in your values." >&2
  exit 1
fi

set -a
source .env
set +a

kubectl create namespace ohs --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic ohs-credentials -n ohs \
  --from-literal=ehrbase-user-password="${EHRBASE_USER_PASSWORD}" \
  --from-literal=ehrbase-db-password="${EHRBASE_DB_PASSWORD}" \
  --from-literal=ehrbase-admin-password="${EHRBASE_ADMIN_PASSWORD}" \
  --from-literal=eos-db-password="${EOS_DB_PASSWORD}" \
  --from-literal=redis-password="${REDIS_PASSWORD}" \
  --from-literal=openfhir-mongo-uri="mongodb://openfhir:${OPENFHIR_MONGO_PASSWORD}@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir?replicaSet=mongodb-cluster&authSource=openfhir&authMechanism=SCRAM-SHA-256" \
  --from-literal=keycloak-admin-password="${KEYCLOAK_ADMIN_PASSWORD}" \
  --from-literal=numportal-keycloak-secret="${NUMPORTAL_KEYCLOAK_SECRET}" \
  --from-literal=numportal-pseudonymity-secret="${NUMPORTAL_PSEUDONYMITY_SECRET}" \
  --from-literal=openehrtool-jwt-secret="${OPENEHRTOOL_JWT_SECRET:-change-me-in-production}" \
  --dry-run=client -o yaml | kubectl apply -f -

# MongoDB root/admin user.
kubectl create secret generic mongodb-root-password -n ohs \
  --from-literal=password="${MONGODB_ROOT_PASSWORD:-change_me}" \
  --dry-run=client -o yaml | kubectl apply -f -

# MongoDB Community user for OpenFHIR.
kubectl create secret generic mongodb-openfhir-password -n ohs \
  --from-literal=password="${OPENFHIR_MONGO_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# CNPG application user for the main EHRbase database.
kubectl create secret generic postgres-cluster-app -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="ehrbase" \
  --from-literal=password="${EHRBASE_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# CNPG managed role for EOS.
kubectl create secret generic postgres-eos-user-secret -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="eos" \
  --from-literal=password="${EOS_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# CNPG managed role for Keycloak.
kubectl create secret generic postgres-keycloak-user-secret -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="keycloak" \
  --from-literal=password="${KEYCLOAK_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# CNPG managed role for Cohort Explorer / NUM Portal.
kubectl create secret generic postgres-numportal-user-secret -n ohs \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="numportal" \
  --from-literal=password="${NUMPORTAL_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied in namespace 'ohs'."