# Verification Guide: Open Health Stack

This guide verifies an already deployed Open Health Stack.

For installation, operators, local image builds, and general setup, see [GETTING_STARTED.md](GETTING_STARTED.md).

---

## Pre-Deployment Checks

```bash
# Validate chart syntax and rendering
helm lint . -f values.yaml -f values-local.yaml
helm template ohs . -n ohs -f values-local.yaml > /dev/null

# Check for unfilled placeholders
grep -r "CHANGE_ME\|PIN_VERSION\|YOUR_" . --include="*.yaml" --include="*.yml"
```

---

## Deployment Status

```bash
# Pods
kubectl get pods -n ohs -w

# PostgreSQL cluster
kubectl get cluster -n ohs postgres-cluster -o wide
kubectl get endpoints -n ohs postgres-cluster-rw postgres-cluster-r postgres-cluster-ro -o wide

# MongoDB cluster
kubectl get mongodbcommunity -n ohs mongodb-cluster -o wide

# PVCs
kubectl get pvc -n ohs

# CronJobs
kubectl get cronjob -n ohs
```

Expected:

```text
postgres-cluster    Cluster in healthy state
mongodb-cluster     Running
ohs-ehrsuction      present
```

---

## Service Health

Port-forward services as needed:

```bash
kubectl port-forward svc/ohs-ehrbase 8080:8080 -n ohs
kubectl port-forward svc/ohs-openfhir 8081:8080 -n ohs
kubectl port-forward svc/ohs-eos 8082:8081 -n ohs
kubectl port-forward svc/ohs-keycloak 8083:8080 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-backend 8084:8090 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-frontend 8085:80 -n ohs
```

Run basic checks:

```bash
EHRBASE_PASS=$(kubectl get secret -n ohs ohs-credentials \
  -o jsonpath='{.data.ehrbase-user-password}' | base64 -d)

AUTH=$(printf 'ehrbase_user:%s' "$EHRBASE_PASS" | base64)

# EHRbase: list templates
curl -s -H "Authorization: Basic $AUTH" \
  http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4

# EHRbase: simple AQL query
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"q":"SELECT e/ehr_id/value FROM EHR e"}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/query/aql | jq .

# openFHIR: health endpoint returns 200 "UP" (no actuator; context path is "/")
curl -s http://localhost:8081/health; echo

# Eos: GET should return 405 because /person is POST-only
curl -o /dev/null -w "%{http_code}\n" http://localhost:8082/person

# Keycloak
curl -s http://localhost:8083/auth/realms/master/.well-known/openid-configuration | jq .
```

Expected Eos result:

```text
405
```

---

## Database Access

### PostgreSQL

```bash
PG_PRIMARY=$(kubectl get cluster -n ohs postgres-cluster \
  -o jsonpath='{.status.currentPrimary}')

kubectl exec -n ohs "$PG_PRIMARY" -- \
  psql -U postgres -d ehrbase -c "SELECT version();"

kubectl exec -n ohs "$PG_PRIMARY" -- \
  psql -U postgres -d eos_omop -c "SELECT version();"
```

### PostgreSQL via Port-Forward

```bash
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n ohs
```

In another terminal:

```bash
export PGPASSWORD=$(kubectl get secret postgres-eos-user-secret -n ohs \
  -o jsonpath='{.data.password}' | base64 -d)

psql -h localhost -p 5432 -U eos -d eos_omop
```

Useful OMOP checks:

```bash
psql -h localhost -p 5432 -U eos -d eos_omop -c "
SELECT relname AS table,
       reltuples::bigint AS approx_rows,
       pg_size_pretty(pg_total_relation_size(oid)) AS size
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relkind = 'r'
ORDER BY reltuples DESC;
"

psql -h localhost -p 5432 -U eos -d eos_omop -c "
SELECT 'person' AS tbl, COUNT(*) FROM person
UNION ALL SELECT 'condition_occurrence', COUNT(*) FROM condition_occurrence
UNION ALL SELECT 'measurement', COUNT(*) FROM measurement
UNION ALL SELECT 'drug_exposure', COUNT(*) FROM drug_exposure;
"
```

### MongoDB

```bash
OPENFHIR_MONGO_PASSWORD=$(kubectl get secret -n ohs mongodb-openfhir-password \
  -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -n ohs mongodb-cluster-0 -c mongod -- \
  mongosh "mongodb://openfhir:${OPENFHIR_MONGO_PASSWORD}@localhost:27017/openfhir?authSource=openfhir&authMechanism=SCRAM-SHA-256" \
  --eval 'db.runCommand({ ping: 1 })'
```

Expected:

```text
ok: 1
```

---

## EHRsuction Export Job

Check CronJob and PVC:

```bash
kubectl get cronjob -n ohs ohs-ehrsuction
kubectl get pvc -n ohs | grep ehrsuction
```

Run a manual export:

```bash
JOB="ohs-ehrsuction-manual-$(date +%s)"

kubectl create job -n ohs "$JOB" --from=cronjob/ohs-ehrsuction

sleep 3
kubectl logs -n ohs -f job/"$JOB"
```

Expected output on a fresh EHRbase:

```text
Connection successful to openEHR platform
Counting compositions
Compositions counted: 0
Query was successful.
Finished.
Created ehr_id folders: 0
Composition types: {}
Saved jsons: 0
```

Inspect the export PVC:

```bash
kubectl run -n ohs ehrsuction-export-debug \
  --image=busybox:1.36 \
  --restart=Never \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "debug",
        "image": "busybox:1.36",
        "command": ["sh", "-c", "find /export -maxdepth 6 -print; sleep 3600"],
        "volumeMounts": [
          {
            "name": "export",
            "mountPath": "/export"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "export",
        "persistentVolumeClaim": {
          "claimName": "ohs-ehrsuction-export"
        }
      }
    ]
  }
}'
```

```bash
kubectl logs -n ohs ehrsuction-export-debug
kubectl delete pod -n ohs ehrsuction-export-debug
```

Clean up manual jobs:

```bash
kubectl get jobs -n ohs -o name \
  | grep 'job.batch/ohs-ehrsuction-manual-' \
  | xargs -r kubectl delete -n ohs
```

Enable scheduled execution:

```bash
kubectl patch cronjob -n ohs ohs-ehrsuction \
  -p '{"spec":{"suspend":false}}'
```

Disable scheduled execution:

```bash
kubectl patch cronjob -n ohs ohs-ehrsuction \
  -p '{"spec":{"suspend":true}}'
```

---

## End-to-End Functional Testing

### EHRbase — Create EHR

```bash
EHRBASE_PASS=$(kubectl get secret -n ohs ohs-credentials \
  -o jsonpath='{.data.ehrbase-user-password}' | base64 -d)

AUTH=$(printf 'ehrbase_user:%s' "$EHRBASE_PASS" | base64)
```

```bash
EHR=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"_type":"EHR_STATUS","archetype_node_id":"openEHR-EHR-EHR_STATUS.generic.v1","name":{"_type":"DV_TEXT","value":"EHR Status"},"subject":{"external_ref":{"id":{"_type":"GENERIC_ID","value":"patient-001","scheme":"test"},"namespace":"test","type":"PERSON"}},"is_modifiable":true,"is_queryable":true}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/ehr)

EHR_ID=$(echo "$EHR" | jq -r '.ehr_id.value')
echo "Created EHR: $EHR_ID"
```

Verify:

```bash
curl -s -H "Authorization: Basic $AUTH" \
  http://localhost:8080/ehrbase/rest/openehr/v1/ehr/$EHR_ID | jq .

curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"q":"SELECT e/ehr_id/value FROM EHR e"}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/query/aql | jq .
```

### EHRbase — Blood Pressure Template & Composition

This repo bundles a real, verified Operational Template and a matching canonical
composition (sourced from the EHRbase test suite, template_id
`ehrbase_blood_pressure_simple.de.v0`):

- `docs/templates/ehrbase_blood_pressure_simple.de.v0.opt` — the flattened OPT
- `docs/templates/ehrbase_blood_pressure_simple.de.v0.json` — a sample composition

Upload the OPT:

```bash
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/xml" \
  --data-binary @docs/templates/ehrbase_blood_pressure_simple.de.v0.opt \
  http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4

# Verify the template was accepted (expect: "ehrbase_blood_pressure_simple.de.v0")
curl -s -H "Authorization: Basic $AUTH" \
  http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4 | jq '.[]|.template_id'
```

Expected upload status: `201 Created`.

Submit the bundled composition into the EHR created above:

```bash
COMP_RESP=$(curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  --data-binary @docs/templates/ehrbase_blood_pressure_simple.de.v0.json \
  http://localhost:8080/ehrbase/rest/openehr/v1/ehr/$EHR_ID/composition)

echo "$COMP_RESP" | jq '.uid.value'
```

Expected: a composition UID like `<uuid>::local.ehrbase.org::1`.

Confirm it is stored and queryable via AQL:

```bash
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"q":"SELECT COUNT(c) FROM EHR e CONTAINS COMPOSITION c WHERE c/archetype_details/template_id/value = '"'"'ehrbase_blood_pressure_simple.de.v0'"'"'"}' \
  http://localhost:8080/ehrbase/rest/openehr/v1/query/aql | jq '.rows'
```

Expected: `[[1]]` (or higher if you submit more than once).

### Eos — Convert EHRs to OMOP

Trigger EOS to read from EHRbase and write OMOP CDM records.

> **Prerequisite:** Athena vocabularies must be loaded and EOS must be configured with
> `eos.config.omop.athenaVocabulariesPresent=true`. Without vocabularies, concept mapping
> is skipped and the `measurement` table stays empty.

```bash
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://localhost:8082/person
curl -s -X POST -H "Content-Type: application/json" -d '{}' http://localhost:8082/ehr
```

Verify OMOP output (port-forward PostgreSQL first: `kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n ohs`):

```bash
export PGPASSWORD=$(kubectl get secret postgres-eos-user-secret -n ohs \
  -o jsonpath='{.data.password}' | base64 -d)

psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM person;"
psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM measurement;"
```

Expected after the composition above is processed: `person` count ≥ 1.

### Cohort Explorer — End-to-End

Port-forward all required services (each in a separate terminal):

```bash
kubectl port-forward svc/ohs-keycloak              8083:8080 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-backend 8084:8090 -n ohs
kubectl port-forward svc/ohs-cohort-explorer-frontend 8085:80  -n ohs
```

**Verify backend authentication** (the test user is created automatically from the Keycloak realm import):

```bash
KC_TOKEN=$(curl -s -X POST \
  "http://localhost:8083/auth/realms/crr/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=num-portal-webapp&username=testuser&password=test123" \
  | jq -r '.access_token')

echo "Token obtained: ${KC_TOKEN:0:40}..."

curl -s -H "Authorization: Bearer $KC_TOKEN" \
  http://localhost:8084/num-portal/api/v1/cohort | jq .
```

Expected: HTTP 200 with a JSON array (empty `[]` on a fresh install).

**Open the UI in the browser:**

```
http://localhost:8085
```

Log in with `testuser` / `test123`. After login you land on the Cohort Explorer dashboard.
To verify the full pipeline: create a new cohort, add a criterion (e.g. Measurement → Blood Pressure Systolic > 0), and execute — the result count should be ≥ 1 if the EOS transformation above completed successfully.

### openFHIR — Health & Mapping Engine

openFHIR is a FHIRConnect **mapping engine** (openEHR ⇄ FHIR), not a FHIR REST server — there is
no `/fhir/Patient` resource API. Verify it is up and that its endpoints respond:

```bash
# Liveness — returns 200 "UP"
curl -s http://localhost:8081/health; echo

# List configured FhirConnect model mappings (empty until mappings are loaded)
curl -s http://localhost:8081/fc/model | head -c 400; echo
```

Conversion endpoints (require a FhirConnect model + Operational Template to be loaded first):

```bash
# Upload an Operational Template
# curl -s -X POST -H "Content-Type: application/xml" \
#   --data-binary @your-template.opt http://localhost:8081/opt

# Convert an openEHR composition to FHIR
# curl -s -X POST -H "Content-Type: application/json" \
#   --data-binary @composition.json http://localhost:8081/openfhir/tofhir | jq .

# Convert a FHIR resource to an openEHR composition
# curl -s -X POST -H "Content-Type: application/json" \
#   --data-binary @resource.json http://localhost:8081/openfhir/toopenehr | jq .
```

---

## Troubleshooting

```bash
# Pod debugging
kubectl describe pod <pod-name> -n ohs
kubectl logs <pod-name> -n ohs
kubectl logs <pod-name> -n ohs --previous

# Events
kubectl get events -n ohs --sort-by=.metadata.creationTimestamp | tail -n 120

# PostgreSQL
kubectl describe cluster postgres-cluster -n ohs
kubectl get endpoints -n ohs postgres-cluster-rw postgres-cluster-r postgres-cluster-ro -o wide

# MongoDB
kubectl describe mongodbcommunity mongodb-cluster -n ohs

# EHRsuction
kubectl get jobs -n ohs | grep ehrsuction
kubectl logs -n ohs job/<job-name>

# Decode credentials
kubectl get secret ohs-credentials -n ohs -o jsonpath='{.data.ehrbase-user-password}' | base64 -d; echo
kubectl get secret postgres-cluster-app -n ohs -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret postgres-eos-user-secret -n ohs -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret mongodb-openfhir-password -n ohs -o jsonpath='{.data.password}' | base64 -d; echo
```

Common issues and fixes are documented in [DEPLOYMENT.md](DEPLOYMENT.md) under **Production Deployment Notes**.