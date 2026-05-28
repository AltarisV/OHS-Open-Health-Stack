#!/usr/bin/env bash
# load-vocab.sh — Streams ATHENA vocabulary CSVs into the OMOP CDM schema.
#
# This is a one-time operation.  Once loaded the data persists in the CNPG PVC
# and survives pod restarts / Helm upgrades.
#
# Usage:
#   bash load-vocab.sh
#
# Environment overrides (all optional):
#   NAMESPACE     Kubernetes namespace          (default: ohs)
#   VOCAB_DIR     Directory containing CSVs     (default: ./vocab)
#   CDM_SCHEMA    PostgreSQL schema name        (default: public)
#   DB_NAME       OMOP database name            (default: eos_omop)
#   CLUSTER_NAME  CNPG cluster name             (default: postgres-cluster)
#   KUBECTL       kubectl binary / alias        (default: kubectl)
#
# Requirements:
#   kubectl (or set KUBECTL="minikube kubectl --")

set -euo pipefail

NAMESPACE="${NAMESPACE:-ohs}"
VOCAB_DIR="${VOCAB_DIR:-$(cd "$(dirname "$0")/vocab" && pwd)}"
CDM_SCHEMA="${CDM_SCHEMA:-public}"
DB_NAME="${DB_NAME:-eos_omop}"
CLUSTER_NAME="${CLUSTER_NAME:-postgres-cluster}"

# Support both plain kubectl and minikube kubectl
if [[ -z "${KUBECTL:-}" ]]; then
  if command -v kubectl &>/dev/null; then
    KUBECTL="kubectl"
  else
    KUBECTL="minikube kubectl --"
  fi
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

kube() { $KUBECTL "$@"; }

find_primary_pod() {
  local pod
  # CNPG labels the primary instance with cnpg.io/instanceRole=primary
  pod=$(kube get pods -n "$NAMESPACE" \
    -l "cnpg.io/instanceRole=primary,cnpg.io/cluster=${CLUSTER_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [[ -z "$pod" ]]; then
    # Fallback: any pod in the cluster (works for single-instance dev setups)
    pod=$(kube get pods -n "$NAMESPACE" \
      -l "cnpg.io/cluster=${CLUSTER_NAME}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi

  echo "$pod"
}

psql_exec() {
  local pod="$1"; shift
  kube exec -n "$NAMESPACE" "$pod" -- psql -U postgres -d "$DB_NAME" "$@"
}

# Stream a local CSV into the database via COPY FROM STDIN.
# This never copies the file to the pod — data is piped through kubectl exec.
load_table() {
  local table="$1"
  local csv_file="$2"
  local pod="$3"

  if [[ ! -f "$csv_file" ]]; then
    echo "  [SKIP] $table — $(basename "$csv_file") not found"
    return 0
  fi

  # Extract column names from the CSV header.
  # Hibernate may create table columns in a different physical order than the
  # Athena CSV export, so we pass an explicit column list to COPY so that
  # PostgreSQL maps by name instead of position.
  local col_list
  col_list=$(head -1 "$csv_file" | tr '[:upper:]' '[:lower:]' | tr '\t' ',')

  local size
  size=$(du -sh "$csv_file" | cut -f1)
  echo "  ┌ $table ($size)"
  printf "  └ "

  # We prepend SQL lines before the CSV data so psql (via -f -) processes them
  # in the same session/stream:
  #
  #   SET session_replication_role = replica — disables FK trigger checks.
  #     Required for circular FK refs (concept ↔ concept_class ↔ domain ↔ vocab).
  #     Automatically resets when the session ends.
  #
  #   NULL '\N' — in CSV mode the default null string is '' (unquoted empty field
  #     = NULL).  Changing it to '\N' means empty fields become '' (empty string),
  #     satisfying NOT NULL constraints like vocabulary.vocabulary_version.
  #
  #   -v ON_ERROR_STOP=1 — make psql exit immediately on any SQL error instead of
  #     continuing to read the remaining CSV bytes as SQL statements.
  {
    printf "SET session_replication_role = replica;\n"
    printf "COPY %s.%s (%s) FROM STDIN WITH (FORMAT csv, DELIMITER E'\\t', HEADER true, QUOTE E'\\b', NULL '\\N');\n" \
      "$CDM_SCHEMA" "$table" "$col_list"
    if command -v pv &>/dev/null; then
      pv -petrs "$(stat -c%s "$csv_file")" "$csv_file"
    else
      dd if="$csv_file" bs=4M status=progress
    fi
  } | kube exec -i -n "$NAMESPACE" "$pod" -- \
    psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 -f -

  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "======================================================"
echo " EOS OMOP Vocabulary Loader"
echo "======================================================"
echo " Namespace : $NAMESPACE"
echo " Schema    : $CDM_SCHEMA"
echo " Database  : $DB_NAME"
echo " Vocab dir : $VOCAB_DIR"
echo "======================================================"
echo ""

PRIMARY_POD=$(find_primary_pod)
if [[ -z "$PRIMARY_POD" ]]; then
  echo "ERROR: Could not find a running pod for CNPG cluster '${CLUSTER_NAME}' in namespace '${NAMESPACE}'." >&2
  echo "  Check: $KUBECTL get pods -n $NAMESPACE -l cnpg.io/cluster=${CLUSTER_NAME}" >&2
  exit 1
fi
echo "Primary pod : $PRIMARY_POD"
echo ""

# Verify the schema tables exist before loading
TABLE_COUNT=$(psql_exec "$PRIMARY_POD" -t -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${CDM_SCHEMA}' AND table_name='concept';" \
  2>/dev/null | tr -d ' ')

if [[ "$TABLE_COUNT" != "1" ]]; then
  echo "ERROR: OMOP CDM tables not found in schema '${CDM_SCHEMA}' of database '${DB_NAME}'." >&2
  echo "  The DDL setup may not have run.  Check the omop-ddl-setup Job in the Helm chart." >&2
  exit 1
fi

# Check whether vocab is already loaded
CONCEPT_COUNT=$(psql_exec "$PRIMARY_POD" -t -c \
  "SELECT COUNT(*) FROM ${CDM_SCHEMA}.concept;" 2>/dev/null | tr -d ' ')

if [[ "$CONCEPT_COUNT" -gt "0" ]]; then
  echo "Vocabulary already loaded (concept table has ${CONCEPT_COUNT} rows)."
  echo "To reload, pass FORCE_RELOAD=1."
  if [[ "${FORCE_RELOAD:-0}" != "1" ]]; then
    exit 0
  fi
  echo "FORCE_RELOAD=1 set — reloading ..."
fi

# Always truncate all vocab tables before loading.  Even on a first run some
# tables (e.g. concept_class, domain) may already have rows from a previous
# failed attempt.  Starting clean avoids duplicate-key violations.
# Uses a DO block so tables that don't exist yet are silently skipped.
echo "Truncating vocab tables ..."
psql_exec "$PRIMARY_POD" -c "
DO \$\$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'drug_strength','concept','concept_relationship',
    'concept_ancestor','concept_synonym','vocabulary',
    'relationship','concept_class','domain'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = '${CDM_SCHEMA}' AND table_name = t
    ) THEN
      EXECUTE format('TRUNCATE ${CDM_SCHEMA}.%I CASCADE', t);
    END IF;
  END LOOP;
END \$\$;"

echo "Loading vocabulary tables (streaming via stdin — no file transfer to pod)..."
if command -v pv &>/dev/null; then
  echo "  progress: pv $(pv --version | head -1)"
else
  echo "  progress: dd status=progress  (install pv for a nicer bar)"
fi
echo ""

# Drop all primary-key constraints on vocab tables before loading.
# Hibernate/JPA creates PKs based on @Id annotations which often differ from
# the OMOP CDM composite PKs (e.g. concept_ancestor needs a composite PK on
# ancestor_concept_id + descendant_concept_id, but JPA makes a single-column PK).
# The OHDSI indices script recreates all PKs and indices correctly afterwards.
echo "Dropping vocab-table PKs (will be recreated by OHDSI indices script) ..."
psql_exec "$PRIMARY_POD" -c "
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT tc.table_name, tc.constraint_name
    FROM information_schema.table_constraints tc
    WHERE tc.constraint_type = 'PRIMARY KEY'
      AND tc.table_schema   = '${CDM_SCHEMA}'
      AND tc.table_name IN (
        'concept','vocabulary','domain','concept_class','relationship',
        'concept_relationship','concept_ancestor','concept_synonym','drug_strength'
      )
  LOOP
    EXECUTE format('ALTER TABLE ${CDM_SCHEMA}.%I DROP CONSTRAINT IF EXISTS %I CASCADE',
                   r.table_name, r.constraint_name);
  END LOOP;
END \$\$;"
echo ""

# Create vocab tables that EOS/Hibernate does not manage (it only creates the
# tables for entities it maps, so concept_synonym and drug_strength are absent).
echo "Creating missing vocab tables (if not exists) ..."
psql_exec "$PRIMARY_POD" -c "
CREATE TABLE IF NOT EXISTS ${CDM_SCHEMA}.concept_synonym (
  concept_id            integer       NOT NULL,
  concept_synonym_name  varchar(1000) NOT NULL,
  language_concept_id   integer       NOT NULL
);
CREATE TABLE IF NOT EXISTS ${CDM_SCHEMA}.drug_strength (
  drug_concept_id           integer NOT NULL,
  ingredient_concept_id     integer NOT NULL,
  amount_value              numeric,
  amount_unit_concept_id    integer,
  numerator_value           numeric,
  numerator_unit_concept_id integer,
  denominator_value         numeric,
  denominator_unit_concept_id integer,
  box_size                  integer,
  valid_start_date          date    NOT NULL,
  valid_end_date            date    NOT NULL,
  invalid_reason            varchar(1)
);"
echo ""

# Load order respects foreign-key dependencies:
#   concept_class / domain / vocabulary → concept → everything else
load_table "concept_class"        "$VOCAB_DIR/CONCEPT_CLASS.csv"        "$PRIMARY_POD"
load_table "domain"               "$VOCAB_DIR/DOMAIN.csv"               "$PRIMARY_POD"
load_table "vocabulary"           "$VOCAB_DIR/VOCABULARY.csv"           "$PRIMARY_POD"
load_table "relationship"         "$VOCAB_DIR/RELATIONSHIP.csv"         "$PRIMARY_POD"
load_table "concept"              "$VOCAB_DIR/CONCEPT.csv"              "$PRIMARY_POD"
load_table "concept_relationship" "$VOCAB_DIR/CONCEPT_RELATIONSHIP.csv" "$PRIMARY_POD"
load_table "concept_ancestor"     "$VOCAB_DIR/CONCEPT_ANCESTOR.csv"     "$PRIMARY_POD"
load_table "concept_synonym"      "$VOCAB_DIR/CONCEPT_SYNONYM.csv"      "$PRIMARY_POD"
load_table "drug_strength"        "$VOCAB_DIR/DRUG_STRENGTH.csv"        "$PRIMARY_POD"

echo ""
echo "======================================================"
echo " Verification"
echo "======================================================"
psql_exec "$PRIMARY_POD" -c "
SELECT table_name, to_char(COUNT(*), 'FM999,999,999') AS rows
FROM (
  SELECT 'concept'              AS table_name, COUNT(*) FROM ${CDM_SCHEMA}.concept
  UNION ALL SELECT 'vocabulary',              COUNT(*) FROM ${CDM_SCHEMA}.vocabulary
  UNION ALL SELECT 'concept_class',           COUNT(*) FROM ${CDM_SCHEMA}.concept_class
  UNION ALL SELECT 'domain',                  COUNT(*) FROM ${CDM_SCHEMA}.domain
  UNION ALL SELECT 'relationship',            COUNT(*) FROM ${CDM_SCHEMA}.relationship
  UNION ALL SELECT 'concept_relationship',    COUNT(*) FROM ${CDM_SCHEMA}.concept_relationship
  UNION ALL SELECT 'concept_ancestor',        COUNT(*) FROM ${CDM_SCHEMA}.concept_ancestor
  UNION ALL SELECT 'concept_synonym',         COUNT(*) FROM ${CDM_SCHEMA}.concept_synonym
  UNION ALL SELECT 'drug_strength',           COUNT(*) FROM ${CDM_SCHEMA}.drug_strength
) t ORDER BY table_name;"

echo ""
echo "Vocabulary loaded successfully."

# ---------------------------------------------------------------------------
# Apply OHDSI performance indices
# (EOS/JPA creates the tables and PKs on startup, but not the secondary
# indices from the OHDSI DDL package.  They are critical for concept lookups.)
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo " Applying OHDSI performance indices"
echo "======================================================"
echo " Downloading OMOPCDM_postgresql_5.4_indices.sql from OHDSI/CommonDataModel ..."

INDICES_URL="https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/postgresql/OMOPCDM_postgresql_5.4_indices.sql"
TMP_IDX=$(mktemp /tmp/omop-indices-XXXXXX.sql)
trap "rm -f $TMP_IDX" EXIT

if command -v curl &>/dev/null; then
  curl -fsSL "$INDICES_URL" -o "$TMP_IDX"
elif command -v wget &>/dev/null; then
  wget -qO "$TMP_IDX" "$INDICES_URL"
else
  echo "  WARNING: Neither curl nor wget found — skipping index creation."
  echo "  Download manually: $INDICES_URL"
  echo "  Replace @cdmDatabaseSchema with '$CDM_SCHEMA' and run against $DB_NAME."
  TMP_IDX=""
fi

if [[ -n "$TMP_IDX" && -s "$TMP_IDX" ]]; then
  # Replace placeholder with the configured schema
  sed -i "s/@cdmDatabaseSchema/${CDM_SCHEMA}/g" "$TMP_IDX"

  echo " Creating indices (this runs CLUSTER on several large tables — may take minutes) ..."
  # Run with ON_ERROR_STOP=0 so already-existing indices don't abort the whole script.
  # Use -i to forward the local SQL file through stdin to psql inside the pod.
  kube exec -i -n "$NAMESPACE" "$PRIMARY_POD" -- \
    psql -U postgres -d "$DB_NAME" --set ON_ERROR_STOP=0 -q -f - \
    < "$TMP_IDX" || true
  echo " Indices created."
fi

echo ""
echo "======================================================"
echo " All done"
echo "======================================================"
echo ""
echo "Next steps:"
echo "  1. Optionally remove the local vocab/ CSVs to free disk space."
echo "  2. The EOS application should now return data from its ETL endpoints."
