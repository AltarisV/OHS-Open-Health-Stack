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

Quick health checks (PowerShell):

```powershell
$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("ehrbase_user:YOUR_PASSWORD"))

# EHRbase — list templates (empty array is expected on fresh install)
Invoke-RestMethod "http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4" `
  -Headers @{Authorization=$auth}

# openFHIR — list operational templates (empty array expected on fresh install)
Invoke-RestMethod "http://localhost:8081/opt"  # or open http://localhost:8081/ for Swagger UI

# Eos — responds 405 (POST-only) confirming the endpoint exists
Invoke-WebRequest "http://localhost:8082/person" -Method GET  # expect: 405 Method Not Allowed
```

---

## End-to-End Functional Testing

### Load OMOP CDM Vocabulary Tables (required for Eos mappings)

Hibernate auto-creates entity-mapped OMOP tables on Eos startup, but vocabulary reference tables
(CONCEPT, VOCABULARY, etc.) must be loaded manually before mappings will produce output.

1. Download vocabularies from [Athena](https://athena.ohdsi.org/) — minimum: SNOMED, LOINC, RxNorm, ICD10CM.
2. Download the OMOP CDM v5.4 DDL from the [OHDSI CommonDataModel repo](https://github.com/OHDSI/CommonDataModel/tree/main/inst/ddl/5.4/postgresql).
3. Forward the PostgreSQL port and load:

```powershell
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n ohs

$env:PGPASSWORD = kubectl get secret postgres-eos-user-secret -n ohs `
  -o jsonpath="{.data.password}" |
  ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }

psql -h localhost -p 5432 -U eos -d eos_omop -f OMOP_CDM_postgresql_5.4_ddl.sql
psql -h localhost -p 5432 -U eos -d eos_omop -f OMOP_CDM_vocabulary_load.sql  # edit CSV paths first

psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM concept;"
```

### EHRbase — create EHR and upload template

```powershell
$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("ehrbase_user:YOUR_PASSWORD"))
$headers = @{Authorization=$auth; "Content-Type"="application/json"; Prefer="return=representation"}

# Create an EHR
$body = '{"_type":"EHR_STATUS","archetype_node_id":"openEHR-EHR-EHR_STATUS.generic.v1","name":{"_type":"DV_TEXT","value":"EHR Status"},"subject":{"external_ref":{"id":{"_type":"GENERIC_ID","value":"patient-001","scheme":"test"},"namespace":"test","type":"PERSON"}},"is_modifiable":true,"is_queryable":true}'
$ehr = Invoke-RestMethod "http://localhost:8080/ehrbase/rest/openehr/v1/ehr" -Method POST -Headers $headers -Body $body
$ehrId = $ehr.ehr_id.value

# Upload an openEHR template (OPT file)
# Invoke-RestMethod "http://localhost:8080/ehrbase/rest/openehr/v1/definition/template/adl1.4" `
#   -Method POST -Headers @{Authorization=$auth; "Content-Type"="application/xml"} -InFile "template.opt"

# Submit a composition (requires template uploaded first)
# Invoke-RestMethod "http://localhost:8080/ehrbase/rest/openehr/v1/ehr/$ehrId/composition" `
#   -Method POST -Headers $headers -Body $compositionJson
```

### Eos — convert EHRs to OMOP

```powershell
# Convert all EHRs to OMOP PERSON records
Invoke-RestMethod "http://localhost:8082/person" -Method POST -ContentType "application/json" -Body "{}"

# Convert all compositions to OMOP CDM records
Invoke-RestMethod "http://localhost:8082/ehr" -Method POST -ContentType "application/json" -Body "{}"

# Verify
psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM person;"
psql -h localhost -p 5432 -U eos -d eos_omop -c "SELECT COUNT(*) FROM measurement;"
```

### openFHIR — FHIR queries

```powershell
Invoke-RestMethod "http://localhost:8081/fhir/Patient"
Invoke-RestMethod "http://localhost:8081/fhir/Patient?identifier=$ehrId"
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
