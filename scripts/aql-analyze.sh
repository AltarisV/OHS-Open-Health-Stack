#!/usr/bin/env bash
# aql-analyze.sh - Das SQL, das EHRbase fuer ein AQL-Kriterium erzeugt, direkt in
# PostgreSQL erklaeren, auf Wunsch mit gemessenen Laufzeiten.
#
# aql-explain.sh zeigt nur die Schaetzung des Planers. Wo die Zeit wirklich bleibt,
# zeigt erst EXPLAIN (ANALYZE, BUFFERS), und das fuehrt die Abfrage aus - hier direkt
# in der Datenbank, mit eigener Zeitgrenze und am Gateway vorbei. Ausgegeben werden
# nur Planknoten, Zeilenzahlen und Zeiten, keine Ergebniszeilen.
#
#   bash scripts/aql-analyze.sh <verzeichnis> <nr> [--analyze] [--set name=wert] [--timeout sek]
#
#   <verzeichnis>  Ausgabe von aql-explain.sh (aql-explain-<zeit>/), gelesen wird <nr>.response.json
#   --analyze      Abfrage ausfuehren: EXPLAIN (ANALYZE, BUFFERS), mit I/O-Zeiten
#   --set          Planereinstellung nur fuer diese Sitzung, mehrfach moeglich,
#                  z. B. --set enable_material=off
#   --timeout      statement_timeout in Sekunden, Vorgabe 3600
#
# Lange Laeufe von der Sitzung loesen, sonst endet die Messung mit dem Terminal:
#   nohup bash scripts/aql-analyze.sh aql-explain-<zeit> 11 --analyze > ~/analyze-11.txt 2>&1 &

set -euo pipefail
NS=${NS:-ohs}
REL=${REL:-ohs}
PGCLUSTER=${PGCLUSTER:-postgres-cluster}
DB=${DB:-ehrbase}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

hilfe() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || hilfe
DIR=$1 NR=$2
shift 2
ANALYZE=0 TIMEOUT=3600 SETS=()
while [ $# -gt 0 ]; do
  case $1 in
    --analyze) ANALYZE=1 ;;
    --set)
      [[ ${2:-} =~ ^[a-z_]+=[A-Za-z0-9_.]+$ ]] || { echo "--set erwartet name=wert" >&2; exit 2; }
      SETS+=("$2"); shift ;;
    --timeout)
      [[ ${2:-} =~ ^[0-9]+$ ]] || { echo "--timeout erwartet Sekunden" >&2; exit 2; }
      TIMEOUT=$2; shift ;;
    *) echo "unbekannte Option: $1" >&2; hilfe ;;
  esac
  shift
done

ANTWORT="$DIR/$NR.response.json"
[ -f "$ANTWORT" ] || { echo "$ANTWORT fehlt - erst aql-explain.sh laufen lassen" >&2; exit 1; }
SQL=$(jq -r '.meta.executed_sql // empty' "$ANTWORT")
[ -n "$SQL" ] || { echo "kein SQL in $ANTWORT (debuggingEnabled beim Probelauf aus?)" >&2; exit 1; }

# Offset und Limit bindet EHRbase als Parameter. Eingesetzt wird, was es selbst
# einsetzt: 0 und das defaultLimit des Deployments.
LIMIT=$(helm get values "$REL" -n "$NS" -a -o json 2>/dev/null | jq -r '.ehrbase.config.aql.defaultLimit // empty' || true)
LIMIT=${LIMIT:-200000}
SQL=${SQL//offset \? rows fetch next \? rows only/offset 0 rows fetch next $LIMIT rows only}
if [[ $SQL == *\?* ]]; then
  echo "das SQL enthaelt weitere Parameter ('?'), die dieses Skript nicht einsetzen kann" >&2
  exit 1
fi

PG=$(kubectl -n "$NS" get cluster "$PGCLUSTER" -o jsonpath='{.status.currentPrimary}')
[ -n "$PG" ] || { echo "Primaerinstanz von $PGCLUSTER nicht gefunden" >&2; exit 1; }

NAME=$(jq -r --argjson i "$((NR - 1))" '.[$i].name // "?"' "$REPO/scripts/aql-criteria.json" 2>/dev/null || echo "?")
if [ "$ANALYZE" = 1 ]; then ART="ANALYZE, BUFFERS, SETTINGS"; MODUS="ausgefuehrt"; else ART="SETTINGS"; MODUS="nur Plan"; fi
echo "=================================================================="
echo "$NR  $NAME"
echo "   $(date '+%F %T')  |  $MODUS  |  ${SETS[*]:-Standardeinstellungen}  |  Zeitgrenze ${TIMEOUT} s"
{
  echo '\pset pager off'
  echo '\timing on'
  echo "SET statement_timeout = '${TIMEOUT}s';"
  [ "$ANALYZE" = 1 ] && echo "SET track_io_timing = on;"
  for s in ${SETS[@]+"${SETS[@]}"}; do echo "SET ${s%%=*} = '${s#*=}';"; done
  printf 'EXPLAIN (%s) %s;\n' "$ART" "$SQL"
} | kubectl -n "$NS" exec -i "$PG" -c postgres -- psql -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1
