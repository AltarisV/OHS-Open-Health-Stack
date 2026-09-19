#!/usr/bin/env bash
# aql-explain.sh - SQL und Abfrageplan der AQL-Kriterien, ohne sie auszufuehren.
#
# Grundlage fuer Indizes gegen lange inhaltliche Abfragen (M-64): EHRbase liefert
# mit den Headern EHRbase-AQL-Dry-Run, -Executed-SQL und -Query-Plan das erzeugte
# SQL und den PostgreSQL-Plan, im Probelauf als EXPLAIN ohne ANALYZE - die Abfrage
# selbst laeuft nicht. Das geht nur bei ehrbase.config.aql.debuggingEnabled, und
# dann darf jeder angemeldete Aufrufer SQL und Plaene abrufen. Deshalb nur fuer
# die Dauer der Analyse einschalten:
#
#   helm upgrade --install ohs . -n ohs -f values-cloud.yaml \
#     --set ehrbase.config.aql.debuggingEnabled=true
#   bash scripts/aql-explain.sh 9 10 11 12 13 14 15   # Nummern aus aql-criteria.json
#   helm upgrade --install ohs . -n ohs -f values-cloud.yaml
#
# Ohne Nummern werden alle Kriterien erklaert. Ausgabe je Kriterium: HTTP-Status,
# SQL und Plan; die vollstaendigen Antworten liegen in ./aql-explain-<zeit>/.
# Enthalten sind nur AQL, SQL und Schaetzwerte des Planers, keine Daten.
#
# --messen fuehrt die Kriterien wirklich aus, ohne debuggingEnabled, und gibt nur
# Zahlen aus - Dauer, Akten, Zeilen:
#
#   bash scripts/aql-explain.sh --messen 1 2 3 4 5 6 7 8
#
# Je Kriterium zwei Abfragen: COUNT(DISTINCT e/ehr_id/value), die Kohortengroesse,
# die das Portal anzeigt (und kriterienprobe.py misst), und e/ehr_id/value ohne
# DISTINCT, die Form, in der num-portal die Kennungen einer Kohorte abrief, bis
# build-images.sh ihm am 15.09.2026 das DISTINCT mitgab (M-68). Sie liefert eine
# Zeile je Composition und endet am defaultLimit; enthaelt sie weniger
# verschiedene Akten als die Zaehlung, waere eine Kohorte ohne diesen Patch
# gekuerzt. Inhaltliche Kriterien (9-15) laufen ohne passenden Index je Abfrage
# bis zu einer Stunde (MAX_TIME, Vorgabe 3600 s).

set -uo pipefail
NS=${NS:-ohs}
REL=${REL:-ohs}
PORT=${PORT:-18080}
cd "$(dirname "$(readlink -f "$0")")/.."
KRITERIEN=scripts/aql-criteria.json
OUT="aql-explain-$(date +%Y%m%d_%H%M)"

# Gibt SQL und Plan einer gespeicherten Antwort aus; der Plan kommt als Objekt mit
# Textfeld oder als EXPLAIN-JSON, beides wird lesbar gemacht.
zeige() {
  local antwort="$1"
  if ! jq -e '.meta' "$antwort" >/dev/null 2>&1; then
    echo "-- keine Ergebnisbeschreibung; Antwort (gekuerzt):"
    head -c 600 "$antwort"; echo
    return
  fi
  if ! jq -e '.meta.executed_sql' "$antwort" >/dev/null 2>&1; then
    echo "-- kein SQL in der Antwort: ist ehrbase.config.aql.debuggingEnabled gesetzt?"
    return
  fi
  echo "-- SQL:"
  jq -r '.meta.executed_sql' "$antwort"
  echo "-- Plan:"
  jq -r '
    .meta.query_plan
    | if type == "object" and (.plan | type) == "string" then .plan
      elif type == "string" then .
      else tojson end' "$antwort"
}

# Nur zum Testen der Ausgabe ohne Cluster: bash aql-explain.sh --zeige <datei>
if [ "${1:-}" = "--zeige" ]; then zeige "$2"; exit 0; fi

MODUS=erklaeren
if [ "${1:-}" = "--messen" ]; then MODUS=messen; shift; fi
MAX_TIME=${MAX_TIME:-3600}

# Fuehrt ein Kriterium in beiden Formen aus (siehe Kopf). Die Antwort der zweiten
# Form enthaelt Aktenkennungen; sie wird nur gezaehlt und sofort geloescht.
messe() {
  local n=$1 form p code zeit tmp kohorte="?" zeilen="?" akten="?" a_text p_text flag=""
  tmp=$(mktemp)
  for form in anzahl portal; do
    if [ "$form" = anzahl ]; then p='SELECT COUNT(DISTINCT e/ehr_id/value)'; else p='SELECT e/ehr_id/value'; fi
    jq -c --argjson i "$((n - 1))" --arg p "$p" \
      '.[$i] | {q: (.query | gsub("\\s+"; " ") | sub("^SELECT e FROM "; $p + " FROM "))}' \
      "$KRITERIEN" > "$OUT/$n.$form.request.json"
    read -r code zeit < <(printf 'user = "%s:%s"\n' "$EHRUSER" "$EHRPW" |
      curl -s -K - -o "$tmp" -w '%{http_code} %{time_total}\n' --max-time "$MAX_TIME" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --data @"$OUT/$n.$form.request.json" \
        "http://localhost:$PORT/ehrbase/rest/openehr/v1/query/aql")
    if [ "$form" = anzahl ]; then
      kohorte=$(jq -r '.rows[0][0] // "?"' "$tmp" 2>/dev/null || echo "?")
      a_text="Anzahl $kohorte (HTTP $code, $zeit s)"
    else
      read -r zeilen akten < <(jq -r '"\(.rows | length) \([.rows[][0]] | unique | length)"' "$tmp" 2>/dev/null || echo "? ?")
      p_text="ohne DISTINCT $zeilen Zeilen, $akten Akten (HTTP $code, $zeit s)"
    fi
    rm -f "$tmp"
  done
  if [[ $kohorte =~ ^[0-9]+$ && $akten =~ ^[0-9]+$ ]] && [ "$akten" -lt "$kohorte" ]; then
    flag="  <- ohne DISTINCT gekuerzt"
  fi
  printf '%-3s %-40s  %s  |  %s%s\n' "$n" "$(jq -r ".[$((n - 1))].name" "$KRITERIEN" | cut -c1-40)" \
    "$a_text" "$p_text" "$flag"
}

mkdir -p "$OUT"
EHRUSER=$(helm get values "$REL" -n "$NS" -a -o json 2>/dev/null | jq -r '.ehrbase.config.auth.username // "ehrbase_user"')
EHRPW=$(kubectl -n "$NS" get secret ohs-credentials -o jsonpath='{.data.ehrbase-user-password}' | base64 -d)

kubectl -n "$NS" port-forward "svc/$REL-ehrbase" "$PORT:8080" >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for _ in $(seq 1 30); do
  curl -s -o /dev/null "http://localhost:$PORT/ehrbase/management/health/liveness" && break
  sleep 0.5
done

anzahl=$(jq length "$KRITERIEN")
if [ $# -gt 0 ]; then auswahl=("$@"); else mapfile -t auswahl < <(seq 1 "$anzahl"); fi

for n in "${auswahl[@]}"; do
  if ! [[ $n =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "$anzahl" ]; then
    echo "Kriterium $n gibt es nicht (1-$anzahl)"; continue
  fi
  if [ "$MODUS" = messen ]; then messe "$n"; continue; fi
  # Der Katalog steht in der Schreibweise des AQL-Builders (SELECT e FROM EHR e ...),
  # die EHRbase selbst ablehnt ("selecting the full EHR object"). num-portal setzt
  # beim Ausfuehren e/ehr_id/value als Projektion ein; hier dieselbe Form, mit DISTINCT.
  jq -c --argjson i "$((n - 1))" \
    '.[$i] | {q: (.query | gsub("\\s+"; " ") | sub("^SELECT e FROM "; "SELECT DISTINCT e/ehr_id/value FROM "))}' \
    "$KRITERIEN" > "$OUT/$n.request.json"
  # Zugangsdaten ueber stdin, damit das Passwort nicht in der Prozessliste steht
  code=$(printf 'user = "%s:%s"\n' "$EHRUSER" "$EHRPW" |
    curl -s -K - -o "$OUT/$n.response.json" -w '%{http_code}' \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      -H 'EHRbase-AQL-Dry-Run: true' -H 'EHRbase-AQL-Executed-SQL: true' \
      -H 'EHRbase-AQL-Query-Plan: true' \
      --data @"$OUT/$n.request.json" \
      "http://localhost:$PORT/ehrbase/rest/openehr/v1/query/aql")
  echo "=================================================================="
  echo "$n  $(jq -r ".[$((n - 1))].name" "$KRITERIEN")  (HTTP $code)"
  echo "-- AQL wie ausgefuehrt: $(jq -r '.q' "$OUT/$n.request.json")"
  zeige "$OUT/$n.response.json"
done
echo "=================================================================="
echo "Vollstaendige Antworten: $OUT/"
