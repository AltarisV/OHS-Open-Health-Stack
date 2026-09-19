#!/usr/bin/env bash
# Forward OHS cluster services to localhost for local development and test-ui access.
#
# Usage:
#   ./scripts/port-forward.sh             # default namespace: ohs
#   ./scripts/port-forward.sh my-ns       # custom namespace
#
# Local ports:
#   8080 → ehrbase                  (EHRbase REST API)
#   8081 → openfhir                 (openFHIR mapping engine)
#   8082 → eos                      (EOS OMOP mapping API)
#   8083 → keycloak                 (Keycloak auth)
#   8084 → cohort-explorer-backend  (NUMportal API)
#   8085 → cohort-explorer-frontend (Cohort Explorer UI)
#   8086 → openehrtool-frontend     (openEHRTool UI)
#   5000 → openehrtool-backend      (openEHRTool API; port must stay 5000 -
#                                    the frontend bundle calls localhost:5000)

set -euo pipefail

NS="${1:-ohs}"

# Use minikube kubectl if available and context is minikube, otherwise plain kubectl
if command -v minikube &>/dev/null && minikube status -f '{{.Host}}' 2>/dev/null | grep -q Running; then
  KC="minikube kubectl --"
else
  KC="kubectl"
fi

echo "Namespace: $NS"
echo "Killing existing port-forwards..."
pkill -f "kubectl.*port-forward.*$NS" 2>/dev/null || true
sleep 1

echo "Starting port-forwards..."
$KC port-forward svc/ohs-ehrbase                  8080:8080 -n "$NS" &
$KC port-forward svc/ohs-openfhir                 8081:8080 -n "$NS" &
$KC port-forward svc/ohs-eos                      8082:8081 -n "$NS" &
$KC port-forward svc/ohs-keycloak                 8083:8080 -n "$NS" &
$KC port-forward svc/ohs-cohort-explorer-backend  8084:8090 -n "$NS" &
$KC port-forward svc/ohs-cohort-explorer-frontend 8085:80   -n "$NS" &
$KC port-forward svc/ohs-openehrtool-frontend     8086:80   -n "$NS" &
$KC port-forward svc/ohs-openehrtool-backend      5000:5000 -n "$NS" &

echo ""
echo "Ready:"
echo "  http://localhost:8080  EHRbase"
echo "  http://localhost:8081  openFHIR"
echo "  http://localhost:8082  EOS"
echo "  http://localhost:8083  Keycloak"
echo "  http://localhost:8084  Cohort Explorer Backend"
echo "  http://localhost:8085  Cohort Explorer Frontend"
echo "  http://localhost:8086  openEHRTool Frontend"
echo "  http://localhost:5000  openEHRTool Backend"
echo ""
echo "Press Ctrl+C to stop all."

wait
