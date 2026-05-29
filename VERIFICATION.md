# Verification Guide: Open Health Stack

## Pre-Deployment

```bash
# Validate chart syntax and rendering
helm lint . -f values.yaml
helm template ohs . -f values.yaml > /dev/null

# Check for unfilled placeholders
grep -r "CHANGE_ME\|PIN_VERSION\|YOUR_" . --include="*.yaml"
```

---

## Deployment Status

```bash
# All pods should reach 1/1 Running (allow 5-15 min for databases)
kubectl get pods -n ohs -w

# PostgreSQL cluster — expect: "Cluster in healthy state"
kubectl get cluster -n ohs

# MongoDB cluster — expect: Status "Running"
kubectl get mongodbcommunity -n ohs

# PVCs — all should be Bound
kubectl get pvc -n ohs
```

---

## Service Health

Port-forward all services (each in a separate terminal):

```bash
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs
kubectl port-forward svc/ohs-eos 8082:8081 -n ohs
```

Quick health checks:

```bash
AUTH=$(echo -n "ehrbase_user:YOUR_PASSWORD" | base64)

# EHRbase — list templates (empty array is expected on fresh install)
curl -s -H "Authorization: Basic $AUTH" \
  http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4

# openFHIR — list operational templates (empty array expected on fresh install)
curl -s http://localhost:8081/opt  # or open http://localhost:8081/ for Swagger UI

# Eos — responds 405 (POST-only) confirming the endpoint exists
curl -o /dev/null -w "%{http_code}\n" http://localhost:8082/person  # expect: 405
```

---

## Database Access

### Quick psql — no password needed inside the pod

```bash
# Run a query directly in the primary pod (peer auth, no password)
minikube kubectl -- exec -n ohs postgres-cluster-1 -- \
  psql -U postgres -d eos_omop -c "SELECT version();"
```

### Port-forward + external SQL client (DBeaver, DataGrip, pgAdmin, etc.)

```bash
# Forward postgres to localhost
minikube kubectl -- port-forward svc/postgres-cluster-rw 5432:5432 -n ohs &

# Retrieve the superuser password
PGPASSWORD=$(minikube kubectl -- get secret postgres-cluster-superuser -n ohs \
  -o jsonpath='{.data.password}' | base64 -d)

# Connect with psql
PGPASSWORD=$PGPASSWORD psql -h localhost -p 5432 -U postgres -d eos_omop
```

Connect any SQL client to: `localhost:5432`, database `eos_omop`, user `postgres`, password from the command above.

### Useful OMOP queries

```bash
EXEC="minikube kubectl -- exec -n ohs postgres-cluster-1 -- psql -U postgres -d eos_omop -c"

# Table sizes and approximate row counts
$EXEC "SELECT relname AS table, reltuples::bigint AS approx_rows,
         pg_size_pretty(pg_total_relation_size(oid)) AS size
       FROM pg_class
       WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
       ORDER BY reltuples DESC;"

# Vocabulary overview
$EXEC "SELECT vocabulary_id, vocabulary_name FROM vocabulary ORDER BY 1;"

# Concept search
$EXEC "SELECT concept_id, concept_name, domain_id, vocabulary_id
       FROM concept WHERE concept_name ILIKE '%myocardial infarction%' LIMIT 10;"

# Clinical data counts (populated by Eos ETL)
$EXEC "SELECT 'person' AS tbl, COUNT(*) FROM person
       UNION ALL SELECT 'condition_occurrence', COUNT(*) FROM condition_occurrence
       UNION ALL SELECT 'measurement', COUNT(*) FROM measurement
       UNION ALL SELECT 'drug_exposure', COUNT(*) FROM drug_exposure;"
```

---

## End-to-End Functional Testing

### Load OMOP CDM Vocabulary Tables (required for Eos mappings)

Hibernate auto-creates entity-mapped OMOP tables on Eos startup, but vocabulary reference tables
(CONCEPT, VOCABULARY, etc.) must be loaded manually before mappings will produce output.

1. Download vocabularies from [Athena](https://athena.ohdsi.org/) — minimum: SNOMED, LOINC, RxNorm, ICD10CM.
2. Download the OMOP CDM v5.4 DDL from the [OHDSI CommonDataModel repo](https://github.com/OHDSI/CommonDataModel/tree/main/inst/ddl/5.4/postgresql).
3. Forward the PostgreSQL port and load:

```bash
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n ohs &

export PGPASSWORD=$(kubectl get secret postgres-eos-user-secret -n ohs \
  -o jsonpath="{.data.password}" | base64 -d)

psql -h localhost -p 5432 -U eos -d eos_omop -f OMOP_CDM_postgresql_5.4_ddl.sql
psql -h localhost -p 5432 -U eos -d eos_omop -f OMOP_CDM_vocabulary_load.sql  # edit CSV paths first

psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM concept;"
```

### EHRbase — create EHR and upload template

```bash
AUTH=$(echo -n "ehrbase_user:YOUR_PASSWORD" | base64)

# Create an EHR
EHR=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"_type":"EHR_STATUS","archetype_node_id":"openEHR-EHR-EHR_STATUS.generic.v1","name":{"_type":"DV_TEXT","value":"EHR Status"},"subject":{"external_ref":{"id":{"_type":"GENERIC_ID","value":"patient-001","scheme":"test"},"namespace":"test","type":"PERSON"}},"is_modifiable":true,"is_queryable":true}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/ehr)
EHR_ID=$(echo "$EHR" | jq -r '.ehr_id.value')
echo "Created EHR: $EHR_ID"

# Retrieve the EHR by ID
curl -s -H "Authorization: Basic $AUTH" \
  http://localhost:8080/ehrbase/rest/openehr/v1/ehr/$EHR_ID | jq .

# List all EHRs (AQL)
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"q":"SELECT e/ehr_id/value FROM EHR e"}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/query/aql | jq .

# Upload an openEHR template (OPT file)
# curl -s -X POST \
#   -H "Authorization: Basic $AUTH" \
#   -H "Content-Type: application/xml" \
#   --data-binary @template.opt \
#   http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4

# Submit a composition (requires template uploaded first)
# curl -s -X POST \
#   -H "Authorization: Basic $AUTH" \
#   -H "Content-Type: application/json" \
#   -H "Prefer: return=representation" \
#   -d "$COMPOSITION_JSON" \
#   http://localhost:8080/ehrbase/rest/openehr/v1/ehr/$EHR_ID/composition
```

### Eos — convert EHRs to OMOP

```bash
# Convert all EHRs to OMOP PERSON records
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://localhost:8082/person

# Convert all compositions to OMOP CDM records
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://localhost:8082/ehr

# Verify
psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM person;"
psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM measurement;"
```

### openFHIR — FHIR queries

```bash
curl -s http://localhost:8081/fhir/Patient
curl -s "http://localhost:8081/fhir/Patient?identifier=$EHR_ID"
```

---

## Troubleshooting

```bash
# Pod not starting — check events and previous logs
kubectl describe pod <pod-name> -n ohs
kubectl logs <pod-name> -n ohs --previous

# Database not ready — check operator status
kubectl describe cluster postgres-cluster -n ohs
kubectl describe mongodbcommunity mongodb-cluster -n ohs

# Wrong credentials — decode the relevant secret
kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data.ehrbase-user-password}' | base64 -d
kubectl get secret postgres-cluster-app -n ohs -o jsonpath='{.data.password}' | base64 -d
```

Common issues and fixes are documented in [DEPLOYMENT.md](DEPLOYMENT.md) under **Production Deployment Notes**.
