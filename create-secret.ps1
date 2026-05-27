# Creates the ohs-credentials Kubernetes secret from a .env file.
# Usage: Copy-Item .env.example .env; # fill in values; .\create-secret.ps1

$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Error "Error: .env file not found. Copy .env.example and fill in your values."
    exit 1
}

Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([^#=\s][^=]*)=(.*)$') {
        Set-Item -Path "env:$($Matches[1].Trim())" -Value $Matches[2].Trim()
    }
}

kubectl create secret generic ohs-credentials -n ohs `
    --from-literal=ehrbase-user-password="$env:EHRBASE_USER_PASSWORD" `
    --from-literal=ehrbase-db-password="$env:EHRBASE_DB_PASSWORD" `
    --from-literal=eos-db-password="$env:EOS_DB_PASSWORD" `
    --from-literal=redis-password="$env:REDIS_PASSWORD" `
    --from-literal=openfhir-mongo-uri="mongodb://openfhir:$($env:OPENFHIR_MONGO_PASSWORD)@mongodb-cluster-svc.ohs.svc.cluster.local:27017/openfhir"

Write-Host "Secret 'ohs-credentials' created in namespace 'ohs'."
