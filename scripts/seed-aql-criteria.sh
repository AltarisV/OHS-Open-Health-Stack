#!/usr/bin/env bash
# Creates AQL criteria ("Kriterien") in the Cohort Explorer (num-portal) via its REST API.
#
# The criteria are read from a JSON array file (default: scripts/aql-criteria.json) whose
# objects map 1:1 onto the backend's AqlDto:
#   name / purpose / use                         -> the German form fields
#   nameTranslated / purposeTranslated / useTranslated -> the English form fields
#   query                                        -> the AQL (SELECT DISTINCT e/ehr_id/value)
#   publicAql                                    -> visible to all users, not just the owner
#
# POST /aql requires the Keycloak realm role CRITERIA_EDITOR.
# Behind the gateway the backend lives under /num-portal (rewritten to / by the HTTPRoute).
#
# The login password is resolved in this order:
#   1. --password '<pw>'  or the OHS_PASSWORD environment variable
#   2. --password-from-secret <secret>/<key>   (kubectl get secret, base64-decoded)
#   3. the realm import ConfigMap, if it carries a literal credential for the login user
#      (testuser on local setups; research only has the __RESEARCH_USER_PASSWORD__
#       placeholder there - use --password-from-secret ohs-credentials/keycloak-research-password)
#   4. interactive prompt
#
# Usage:
#   bash scripts/seed-aql-criteria.sh --insecure                 # prompts for the password
#   OHS_PASSWORD='<pw>' bash scripts/seed-aql-criteria.sh --insecure
#   bash scripts/seed-aql-criteria.sh --user someone \
#        --password-from-secret ohs-credentials/someone-password --insecure
#   bash scripts/seed-aql-criteria.sh --dry-run          # print payloads, send nothing
#   bash scripts/seed-aql-criteria.sh --list             # show criteria already stored
#   bash scripts/seed-aql-criteria.sh --update --insecure  # replace stored criteria
#        (matches by name and PUTs; without --update a changed catalogue would
#         create a second copy of every criterion)
#
# Port-forward variant (no gateway):
#   kubectl port-forward svc/ohs-keycloak 8083:8080 -n ohs
#   kubectl port-forward svc/ohs-cohort-explorer-backend 8084:8090 -n ohs
#   bash scripts/seed-aql-criteria.sh --auth-url http://localhost:8083/auth \
#        --api-url http://localhost:8084
#
# Requires: bash, curl, jq

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
BASE_URL="${OHS_BASE_URL:-https://ohs.example.org}"
AUTH_URL=""            # derived from BASE_URL as <base>/auth if unset
API_URL=""             # derived from BASE_URL as <base>/num-portal if unset
REALM="crr"
CLIENT_ID="num-portal-webapp"
USERNAME="research"
PASSWORD="${OHS_PASSWORD:-}"
PASSWORD_SECRET=""     # <secret>/<key> in NAMESPACE
NAMESPACE="ohs"
KUBE_CONTEXT=""
REALM_CONFIGMAP="ohs-keycloak-realm"
FILE="$(dirname "$0")/aql-criteria.json"
INSECURE=false
DRY_RUN=false
LIST_ONLY=false
UPDATE=false

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)       BASE_URL="$2"; shift 2 ;;
    --auth-url)  AUTH_URL="$2"; shift 2 ;;
    --api-url)   API_URL="$2";  shift 2 ;;
    --realm)     REALM="$2";    shift 2 ;;
    --client)    CLIENT_ID="$2";shift 2 ;;
    --user)      USERNAME="$2"; shift 2 ;;
    --password)  PASSWORD="$2"; shift 2 ;;
    --password-from-secret) PASSWORD_SECRET="$2"; shift 2 ;;
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --kube-context) KUBE_CONTEXT="$2"; shift 2 ;;
    --realm-configmap) REALM_CONFIGMAP="$2"; shift 2 ;;
    --file)      FILE="$2";     shift 2 ;;
    --insecure)  INSECURE=true; shift ;;
    --dry-run)   DRY_RUN=true;  shift ;;
    --list)      LIST_ONLY=true;shift ;;
    --update)    UPDATE=true;   shift ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

AUTH_URL="${AUTH_URL:-${BASE_URL}/auth}"
API_URL="${API_URL:-${BASE_URL}/num-portal}"

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "Error: '$tool' not found on PATH." >&2; exit 1; }
done
[[ -f "$FILE" ]] || { echo "Error: criteria file not found: $FILE" >&2; exit 1; }

# Corporate proxies may intercept host names; always bypass the proxy for these calls.
CURL=(curl -sS --noproxy '*')
$INSECURE && CURL+=(-k)

# Dry run needs neither cluster nor token.
if $DRY_RUN; then
  echo "→ Dry run: would POST $(jq 'length' "$FILE") criteria to ${API_URL}/aql"
  jq -c '.[]' "$FILE" | while IFS= read -r criterion; do
    echo "── ${criterion}"
  done
  exit 0
fi

# ── Password resolution ───────────────────────────────────────────────────────
kube() {
  local args=(--namespace "$NAMESPACE")
  [[ -n "$KUBE_CONTEXT" ]] && args+=(--context "$KUBE_CONTEXT")
  kubectl "${args[@]}" "$@"
}

# Reads <secret>/<key> and base64-decodes it.
password_from_secret() {
  local ref="$1" secret key value
  secret="${ref%%/*}"; key="${ref#*/}"
  if [[ "$secret" == "$ref" || -z "$key" ]]; then
    echo "Error: --password-from-secret expects <secret>/<key>, got '${ref}'." >&2
    exit 1
  fi
  value=$(kube get secret "$secret" -o "jsonpath={.data.${key}}" 2>/dev/null) || true
  [[ -n "$value" ]] || { echo "Error: key '${key}' not found in secret '${secret}' (namespace ${NAMESPACE})." >&2; exit 1; }
  printf '%s' "$value" | base64 -d
}

# Pulls the credential of the login user out of the imported realm definition.
# Only works for users created by the realm import with a literal password (e.g. testuser);
# placeholders such as __RESEARCH_USER_PASSWORD__ are skipped.
password_from_realm() {
  local realm_json
  realm_json=$(kube get configmap "$REALM_CONFIGMAP" \
    -o 'jsonpath={.data.crr-realm\.json}' 2>/dev/null) || return 1
  [[ -n "$realm_json" ]] || return 1
  jq -er --arg u "$USERNAME" \
    '.users[] | select(.username == $u) | .credentials[]? | select(.type == "password") | .value
     | select(test("^__[A-Z_]+__$") | not)' \
    <<<"$realm_json" 2>/dev/null | head -n1
}

if [[ -z "$PASSWORD" && -n "$PASSWORD_SECRET" ]]; then
  command -v kubectl >/dev/null || { echo "Error: kubectl not found on PATH." >&2; exit 1; }
  echo "→ Reading password from secret ${PASSWORD_SECRET} (namespace ${NAMESPACE})"
  PASSWORD=$(password_from_secret "$PASSWORD_SECRET")
fi

if [[ -z "$PASSWORD" ]] && command -v kubectl >/dev/null; then
  if PASSWORD=$(password_from_realm) && [[ -n "$PASSWORD" ]]; then
    echo "→ Password for '${USERNAME}' taken from configmap ${REALM_CONFIGMAP}"
  else
    PASSWORD=""
  fi
fi

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Password for ${USERNAME}: " PASSWORD; echo
fi

# ── Token ─────────────────────────────────────────────────────────────────────

echo "→ Requesting token from ${AUTH_URL}/realms/${REALM} as ${USERNAME}"
TOKEN_RESPONSE=$("${CURL[@]}" -X POST \
  "${AUTH_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "username=${USERNAME}" \
  --data-urlencode "password=${PASSWORD}")

TOKEN=$(jq -r '.access_token // empty' <<<"$TOKEN_RESPONSE")
if [[ -z "$TOKEN" ]]; then
  echo "Error: no access token received:" >&2
  echo "$TOKEN_RESPONSE" >&2
  exit 1
fi

# Warn early instead of failing on every POST with a 403.
if ! jq -r '.realm_access.roles[]?' \
     <<<"$(printf '%s' "${TOKEN#*.}" | cut -d. -f1 | tr '_-' '/+' | base64 -d 2>/dev/null || echo '{}')" \
     | grep -qx "CRITERIA_EDITOR"; then
  echo "  Warning: token does not carry the CRITERIA_EDITOR role — POST /aql will return 403." >&2
fi

# ── Reading the stored criteria ───────────────────────────────────────────────
# GET /aql/all does not necessarily return a bare array - depending on the
# backend version the list arrives wrapped in a paging object. Normalise both
# shapes, and print the raw payload instead of a cryptic jq error if it is
# neither.
aql_list() {
  local raw normalized
  raw=$("${CURL[@]}" -H "Authorization: Bearer ${TOKEN}" "${API_URL}/aql/all")
  normalized=$(jq -c 'if type == "array" then .
                      else (.content // .items // .data // .aqls // .results // empty) end' \
                <<<"$raw" 2>/dev/null) || true
  if [[ -z "$normalized" ]] || [[ "$(jq -r 'type' <<<"$normalized" 2>/dev/null)" != "array" ]]; then
    echo "Error: unexpected response from GET ${API_URL}/aql/all" >&2
    echo "       (expected an array of criteria, or an object wrapping one):" >&2
    head -c 500 <<<"$raw" >&2; echo >&2
    return 1
  fi
  printf '%s' "$normalized"
}

# ── List mode ─────────────────────────────────────────────────────────────────
if $LIST_ONLY; then
  aql_list | jq -r '.[] | "\(.id)\t\(.name)"'
  exit 0
fi

# ── Seed ──────────────────────────────────────────────────────────────────────
TOTAL=$(jq 'length' "$FILE")
OK=0; FAILED=0

# In update mode, map existing criteria name -> id so a changed catalogue
# replaces what is stored instead of creating a second copy under the same name.
EXISTING="{}"
if $UPDATE; then
  EXISTING=$(aql_list | jq 'map(select(.name != null and .id != null))
                            | map({key: .name, value: .id}) | from_entries')
  echo "→ Update mode: ${API_URL}/aql, $(jq 'length' <<<"$EXISTING") criteria already stored"
else
  echo "→ Posting ${TOTAL} criteria to ${API_URL}/aql"
fi

while IFS= read -r criterion; do
  NAME=$(jq -r '.name' <<<"$criterion")

  METHOD=POST
  URL="${API_URL}/aql"
  if $UPDATE; then
    ID=$(jq -r --arg n "$NAME" '.[$n] // empty' <<<"$EXISTING")
    if [[ -n "$ID" ]]; then
      METHOD=PUT
      URL="${API_URL}/aql/${ID}"
      criterion=$(jq --argjson id "$ID" '. + {id: $id}' <<<"$criterion")
    fi
  fi

  BODY=$("${CURL[@]}" -w '\n%{http_code}' -X "$METHOD" "$URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$criterion")
  CODE=$(tail -n1 <<<"$BODY")
  PAYLOAD=$(sed '$d' <<<"$BODY")

  if [[ "$CODE" =~ ^2 ]]; then
    ID=$(jq -r '.id // "?"' <<<"$PAYLOAD" 2>/dev/null || echo "?")
    printf '  ✓ %-4s %-43s id=%s\n' "$METHOD" "$NAME" "$ID"
    OK=$((OK + 1))
  else
    printf '  ✗ %-4s %-43s HTTP %s\n' "$METHOD" "$NAME" "$CODE"
    echo "      ${PAYLOAD}" | head -c 400; echo
    FAILED=$((FAILED + 1))
  fi
done < <(jq -c '.[]' "$FILE")

$DRY_RUN && exit 0
echo "→ Done: ${OK} written, ${FAILED} failed."
[[ "$FAILED" -eq 0 ]]
