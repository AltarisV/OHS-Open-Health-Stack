#!/usr/bin/env bash
# ehrbase-index.sh - Zusaetzliche Indizes fuer inhaltliche AQL-Filter in EHRbase.
#
# EHRbase richtet alle Indizes auf die einzelne Composition oder Akte aus:
# comp_data beginnt immer mit vo_id, comp_version mit ehr_id. Ein Filter auf einen
# Wert ueber den ganzen Bestand liest deshalb jede Composition des Templates oder
# jeden Knoten des Archetyps (M-64, Plaene aus aql-explain.sh). Ein Ausdrucksindex
# ueber genau den JSON-Ausdruck, den EHRbases SQL fuer die Bedingung benutzt, dreht
# die Richtung um: erst die Treffer, dann die Compositions dazu.
#
# Die Indizes gehoeren nicht zu EHRbase und tragen deshalb das Praefix ohs_. Ihr
# Ausdruck muss dem erzeugten SQL genau entsprechen, sonst bleibt der Index
# ungenutzt. Nach jedem EHRbase-Upgrade mit aql-analyze.sh pruefen, ob der Plan
# ihn noch verwendet.
#
#   bash scripts/ehrbase-index.sh status            Indizes auf comp_data, Nutzung, Platz, laufender Aufbau
#   bash scripts/ehrbase-index.sh schaetzen         Zeilen je Index aus einer Stichprobe von 0,05 %
#   bash scripts/ehrbase-index.sh anlegen <name>    CREATE INDEX CONCURRENTLY
#   bash scripts/ehrbase-index.sh entfernen <name>  DROP INDEX CONCURRENTLY
#
# anlegen liest die Tabelle zweimal ganz (rund 190 GB). Es sperrt dabei weder Lesen
# noch Schreiben, wartet aber auf laufende Transaktionen. Am 15.09.2026 dauerte
# ohs_comp_data_code_idx 8,5 Minuten und belegt 43 MB (schaetzen nannte 144 MB;
# gleiche Schluessel legt PostgreSQL zusammen). Von der Sitzung loesen:
#   nohup bash scripts/ehrbase-index.sh anlegen ohs_comp_data_code_idx > ~/index.txt 2>&1 &

set -euo pipefail
NS=${NS:-ohs}
PGCLUSTER=${PGCLUSTER:-postgres-cluster}
DB=${DB:-ehrbase}

# Name -> "Spalte|Bedingung". Ausdruck und Bedingung wie im SQL von EHRbase 2.31.
declare -A INDEX=(
  # Kodierte Werte an items[at0002]: .../value/defining_code/code_string, etwa der
  # ICD-10-GM-Kode in problem_diagnosis (Kriterien 11 und 12). text_pattern_ops,
  # damit LIKE 'E11*' unabhaengig von der Kollation als Praefixsuche ankommt.
  [ohs_comp_data_code_idx]="((((data -> 'V') -> 'df') -> 'cd') ->> 0) text_pattern_ops|entity_concept = 'at0002' AND entity_attribute = 'i'"
)

hilfe() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
case ${1:-} in status|schaetzen|anlegen|entfernen) ;; *) hilfe ;; esac
PG=$(kubectl -n "$NS" get cluster "$PGCLUSTER" -o jsonpath='{.status.currentPrimary}')
[ -n "$PG" ] || { echo "Primaerinstanz von $PGCLUSTER nicht gefunden" >&2; exit 1; }
# -i nur, wo psql von stdin liest: Unter nohup ist stdin nicht lesbar, und kubectl
# meldet dann "Copying stdin failed", auch wenn der Befehl selbst gelingt.
psql_() { kubectl -n "$NS" exec -i "$PG" -c postgres -- psql -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1 "$@"; }
psql_c() { kubectl -n "$NS" exec "$PG" -c postgres -- psql -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1 "$@"; }
platz() { kubectl -n "$NS" exec "$PG" -c postgres -- df -h /var/lib/postgresql/data | sed 's/^/   /'; }

index_aus_katalog() {
  local def=${INDEX[${1:-}]:-}
  [ -n "$def" ] || { echo "unbekannter Index '${1:-}', bekannt: ${!INDEX[*]}" >&2; exit 2; }
  SPALTE=${def%%|*} BEDINGUNG=${def#*|}
}

case ${1:-} in
  status)
    psql_ <<'SQL'
\pset pager off
\echo Indizes auf ehr.comp_data
SELECT c.relname AS index, pg_size_pretty(pg_relation_size(c.oid)) AS groesse,
       CASE WHEN x.indisvalid THEN 'ja' ELSE 'NEIN - entfernen und neu anlegen' END AS gueltig,
       s.idx_scan AS benutzt
  FROM pg_index x
  JOIN pg_class c ON c.oid = x.indexrelid
  LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = x.indexrelid
 WHERE x.indrelid = 'ehr.comp_data'::regclass
 ORDER BY c.relname;
\echo Laufender Aufbau
SELECT phase, round(100.0 * blocks_done / nullif(blocks_total, 0), 1) AS prozent_bloecke,
       tuples_done AS zeilen, lockers_done || '/' || lockers_total AS gewartet_auf_transaktionen
  FROM pg_stat_progress_create_index;
\echo Transaktionen, die laenger als 5 Minuten laufen (auf sie wartet ein Aufbau)
SELECT pid, application_name, state, date_trunc('second', now() - xact_start) AS seit, wait_event
  FROM pg_stat_activity
 WHERE datname = current_database() AND pid <> pg_backend_pid()
   AND xact_start < now() - interval '5 minutes'
 ORDER BY xact_start;
SQL
    echo "Platz auf dem Datenbankvolume:"
    platz
    ;;
  schaetzen)
    for name in "${!INDEX[@]}"; do
      index_aus_katalog "$name"
      psql_c -At -F ' ' -c "SELECT count(*) * 2000 FROM ehr.comp_data TABLESAMPLE SYSTEM (0.05) WHERE $BEDINGUNG" |
        awk -v n="$name" '{ printf "%s: rund %d Zeilen, grob %.0f MB\n", n, $1, $1 * 24 / 1048576 }'
    done
    echo "Platz auf dem Datenbankvolume:"
    platz
    ;;
  anlegen)
    index_aus_katalog "${2:-}"
    gueltig=$(psql_c -At -c "SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass('ehr.$2')")
    if [ "$gueltig" = t ]; then echo "ehr.$2 existiert bereits"; exit 0; fi
    if [ "$gueltig" = f ]; then
      echo "Rest eines abgebrochenen Aufbaus gefunden, entferne ehr.$2"
      psql_c -c "DROP INDEX CONCURRENTLY ehr.$2"
    fi
    echo "$(date '+%F %T')  lege ehr.$2 an"
    psql_ <<SQL
\timing on
SET statement_timeout = 0;
CREATE INDEX CONCURRENTLY $2 ON ehr.comp_data ($SPALTE) WHERE $BEDINGUNG;
SQL
    echo "$(date '+%F %T')  fertig"
    psql_c -c "SELECT pg_size_pretty(pg_relation_size('ehr.$2')) AS groesse"
    ;;
  entfernen)
    [[ ${2:-} == ohs_* ]] || { echo "entfernt werden nur eigene Indizes (ohs_...)" >&2; exit 2; }
    psql_c -c "DROP INDEX CONCURRENTLY IF EXISTS ehr.$2"
    ;;
  *) hilfe ;;
esac
