#!/usr/bin/env bash
# Builds and pushes self-hosted images required by OHS.
# Repos are cloned into a temporary directory.
#
# Usage:
#   bash build-images.sh [--registry <host:port>] [--tag <tag>] [--skip-push] [--component <name>]
#
# Components: cohort-explorer-backend, cohort-explorer-frontend,
#             openehrtool-backend, openehrtool-frontend,
#             ehrsuction
# Default: build all components.
# Note: cohort-explorer-backend uses 'mvn spring-boot:build-image' (no Dockerfile).
#       Requires JDK 17 + Maven on PATH.
#
# Examples:
#   bash build-images.sh --registry localhost:5000
#   bash build-images.sh --registry registry.example.org --tag v1.0.0
#   bash build-images.sh --registry localhost:5000 --component openehrtool-backend --skip-push

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
REGISTRY=""
TAG="ohs"
SKIP_PUSH=false
ONLY_COMPONENT=""

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag)      TAG="$2";      shift 2 ;;
    --skip-push) SKIP_PUSH=true; shift ;;
    --component) ONLY_COMPONENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REGISTRY" ]]; then
  echo "Error: --registry is required (e.g. localhost:5000 or registry.example.org/ohs)" >&2
  exit 1
fi

# ── Temp workspace ────────────────────────────────────────────────────────────
WORKDIR="$(mktemp -d)"
trap 'echo "Cleaning up $WORKDIR"; rm -rf "$WORKDIR"' EXIT

echo "Build workspace: $WORKDIR"
echo "Registry:        $REGISTRY"
echo "Tag:             $TAG"
echo ""

# ── Helper ────────────────────────────────────────────────────────────────────
build_and_push() {
  local name="$1"      # image name without registry prefix
  local context="$2"   # path to Dockerfile context
  local full_image="${REGISTRY}/${name}:${TAG}"

  shift 2
  local extra_args=("$@")  # any extra --build-arg flags

  echo "──────────────────────────────────────────"
  echo "Building: $full_image"
  docker build "${extra_args[@]}" -t "$full_image" "$context"

  if [[ "$SKIP_PUSH" == false ]]; then
    echo "Pushing:  $full_image"
    docker push "$full_image"
  else
    echo "Skipping push (--skip-push)"
  fi
  echo ""
}

should_build() {
  [[ -z "$ONLY_COMPONENT" || "$ONLY_COMPONENT" == "$1" ]]
}

# ── cohort-explorer-backend ───────────────────────────────────────────────────
# Uses a multi-stage Dockerfile (generated here) so the Maven build runs inside
# a JDK 17 container - no host JDK or Maven required.
if should_build "cohort-explorer-backend"; then
  echo "Cloning cohort-explorer-backend..."
  # COHORT_EXPLORER_BACKEND_REF pins the build to a commit or tag. Rebuilding
  # from the moving develop branch is not a neutral act: the backend runs its
  # Flyway migrations at startup, so a newer develop can alter the numportal
  # schema irreversibly. Pin when the goal is "the running version plus a fix".
  if [[ -n "${COHORT_EXPLORER_BACKEND_REF:-}" ]]; then
    git clone https://github.com/highmed/cohort-explorer-backend \
      "$WORKDIR/cohort-explorer-backend"
    git -C "$WORKDIR/cohort-explorer-backend" checkout --quiet "$COHORT_EXPLORER_BACKEND_REF"
    echo "Pinned to ${COHORT_EXPLORER_BACKEND_REF}."
  else
    git clone --depth 1 https://github.com/highmed/cohort-explorer-backend \
      "$WORKDIR/cohort-explorer-backend"
    echo "WARNING: building from the current develop HEAD ($(git -C "$WORKDIR/cohort-explorer-backend" rev-parse --short HEAD))." >&2
    echo "         Set COHORT_EXPLORER_BACKEND_REF=<commit> to pin. Back up the" >&2
    echo "         numportal database first - Flyway migrates it on startup." >&2
  fi

  # Upstream bug: the AQL editor's containment builder looks up every node's RM
  # type and dereferences the result without checking it. Foundation types such
  # as STRING have no RMTypeInfo, so getTypeInfo returns null and the request
  # dies with a NullPointerException. Any template containing an ACTION
  # archetype with a STRING node is affected - KDS_Prozedur_ISH is, which breaks
  # the whole data-retrieval page for a project that uses it as a return
  # parameter. Skip nodes whose type cannot be resolved; they carry no
  # containment information anyway.
  # Guard the dereference itself rather than inserting an early return: an
  # expression-level fix compiles no matter what the enclosing method returns.
  # An unresolvable type is treated as plain Object, which fails the
  # Locatable check the code performs on it - the node is skipped, which is
  # exactly right for a foundation type that carries no containment.
  python3 - "$WORKDIR/cohort-explorer-backend" <<'PYEOF'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
src = root / "src/main/java/org/highmed/numportal/service/aqleditor/AqlEditorContainmentService.java"
if not src.exists():
    sys.exit(f"Error: {src} not found - upstream layout changed.")
text = src.read_text(encoding="utf-8")
old, new = "typeInfo.getJavaClass()", "(typeInfo == null ? Object.class : typeInfo.getJavaClass())"
if new in text:
    print("Containment null-guard already present.")
    raise SystemExit
count = text.count(old)
if count == 0:
    sys.exit("Error: no 'typeInfo.getJavaClass()' found - patch needs review.")
src.write_text(text.replace(old, new), encoding="utf-8")
print(f"Containment null-guard applied ({count} dereference(s)).")
# Any other use of typeInfo would still be unguarded - say so rather than
# leaving a second NullPointerException to be discovered in production.
rest = [ln.strip() for ln in text.splitlines()
        if "typeInfo." in ln and old not in ln]
for ln in rest:
    print(f"  WARNING: unguarded typeInfo use remains: {ln}", file=sys.stderr)
PYEOF

  # Upstream default: the numportal DataSource is assembled by hand from a bare
  # HikariConfig - driver, URL, user, password and the JDBC driver properties,
  # nothing else. Hikari's own default of ten connections therefore applies, and
  # no property can raise it. Ten is too few here: a data-retrieval request holds
  # its connection for its entire run, so a few of them starve the pool and every
  # other request in the portal fails with "Connection is not available" until the
  # liveness probe kills the pod. Measured 2026-08-27 during a Datenabruf over
  # 105.000 patients: total=10, active=10, waiting=10, then exit 137.
  # The size becomes a property (spring.datasource.numportal.maximum-pool-size,
  # env SPRING_DATASOURCE_NUMPORTAL_MAXIMUM_POOL_SIZE); the old behaviour stays
  # reachable by setting it to 10.
  python3 - "$WORKDIR/cohort-explorer-backend" <<'POOLEOF'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
src = root / "src/main/java/org/highmed/numportal/config/database/NumPortalDatasourceConfiguration.java"
if not src.exists():
    sys.exit(f"Error: {src} not found - upstream layout changed.")
text = src.read_text(encoding="utf-8")
if "setMaximumPoolSize" in text:
    print("Hikari pool size already configurable.")
    raise SystemExit
field_anchor = '  @Value("${spring.jpa.show-sql}")\n  private boolean showSql;\n'
if field_anchor not in text:
    sys.exit("Error: showSql field not found - patch needs review.")
text = text.replace(
    field_anchor,
    field_anchor
    + '\n  @Value("${spring.datasource.numportal.maximum-pool-size:30}")\n'
    + "  private int numPortalMaxPoolSize;\n",
    1)
call_anchor = "    return new HikariDataSource(hikariConfig);"
if text.count(call_anchor) != 1:
    sys.exit("Error: expected exactly one HikariDataSource construction.")
text = text.replace(
    call_anchor,
    "    hikariConfig.setMaximumPoolSize(numPortalMaxPoolSize);\n" + call_anchor,
    1)
src.write_text(text, encoding="utf-8")
print("Hikari pool size made configurable (default 30).")
POOLEOF

  # Upstream bug: a cohort is built from the EHR IDs that
  # EhrBaseService.retrieveEligiblePatientIds fetches per criterion. It parses the
  # stored AQL and swaps the projection for e/ehr_id/value, but keeps the stored
  # query's DISTINCT flag - and the AQL builder stores SELECT e without one. The
  # query then returns one row per matching composition and runs into EHRbase's
  # result limit (ehrbase.config.aql.defaultLimit), which cuts it without an
  # error. Measured 2026-09-15 with a limit of 200,000 (scripts/aql-explain.sh
  # --messen): "Laborbefund vorhanden" kept 40,644 of 84,188 patients,
  # "Vitalparameter vorhanden" 16,344 of 76,848. The editor's count uses
  # COUNT(DISTINCT ...) and was right, so nothing looked wrong. The IDs end up
  # in a Set anyway; DISTINCT changes nothing but the number of rows.
  python3 - "$WORKDIR/cohort-explorer-backend" <<'DISTINCTEOF'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
src = root / "src/main/java/org/highmed/numportal/service/ehrbase/EhrBaseService.java"
if not src.exists():
    sys.exit(f"Error: {src} not found - upstream layout changed.")
text = src.read_text(encoding="utf-8")
anchor = '    log.info("Generated query for retrieveEligiblePatientIds {} ", AqlRenderer.render(dto));\n'
fix = "    dto.getSelect().setDistinct(true);\n"
if fix + anchor in text:
    print("Cohort ID query already DISTINCT.")
    raise SystemExit
if text.count(anchor) != 1:
    sys.exit("Error: retrieveEligiblePatientIds log line not found - patch needs review.")
src.write_text(text.replace(anchor, fix + anchor, 1), encoding="utf-8")
print("Cohort ID query made DISTINCT.")
DISTINCTEOF

  # Generate a multi-stage Dockerfile: compile with JDK 17, run with JRE 17.
  cat > "$WORKDIR/cohort-explorer-backend/Dockerfile" << 'DOCKEREOF'
FROM maven:3.9-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY . .
# Behind an HTTP(S) proxy, Maven's transport ignores HTTP_PROXY env; it needs a
# settings.xml <proxies>. Derive host/port from the proxy Docker injects into the
# build ($HTTPS_PROXY, from ~/.docker/config.json). No proxy set -> no-op.
RUN set -eux; \
    if [ -n "${HTTPS_PROXY:-}" ]; then \
      ph="$(printf '%s' "$HTTPS_PROXY" | sed -E 's#^https?://##; s#/.*$##')"; \
      mkdir -p /root/.m2; \
      printf '<settings><proxies><proxy><id>h</id><active>true</active><protocol>http</protocol><host>%s</host><port>%s</port></proxy><proxy><id>s</id><active>true</active><protocol>https</protocol><host>%s</host><port>%s</port></proxy></proxies></settings>' "${ph%%:*}" "${ph##*:}" "${ph%%:*}" "${ph##*:}" > /root/.m2/settings.xml; \
    fi; \
    mvn package -Dmaven.test.skip=true --no-transfer-progress

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8090
ENTRYPOINT ["java", "-jar", "app.jar"]
DOCKEREOF

  build_and_push "cohort-explorer-backend" "$WORKDIR/cohort-explorer-backend"
fi

# ── cohort-explorer-frontend ──────────────────────────────────────────────────
if should_build "cohort-explorer-frontend"; then
  echo "Cloning cohort-explorer-frontend..."
  git clone --depth 1 https://github.com/highmed/cohort-explorer-frontend \
    "$WORKDIR/cohort-explorer-frontend"

  # Upstream Dockerfile pins node:20.14-alpine; Angular CLI now requires >=20.19.
  sed -i 's|node:20\.14-alpine|node:22-alpine|g' "$WORKDIR/cohort-explorer-frontend/Dockerfile"

  # Run as non-root: switch the runtime stage to nginx-unprivileged (uid 101) and
  # serve on 8080 (non-root cannot bind <1024). pid moves to a writable path.
  sed -i 's|FROM nginx:1\.25-alpine|FROM nginxinc/nginx-unprivileged:1.25-alpine|' "$WORKDIR/cohort-explorer-frontend/Dockerfile"
  sed -i 's|listen 80;|listen 8080;|' "$WORKDIR/cohort-explorer-frontend/nginx.conf"
  grep -q 'pid /tmp/nginx.pid;' "$WORKDIR/cohort-explorer-frontend/nginx.conf" \
    || sed -i '1i pid /tmp/nginx.pid;' "$WORKDIR/cohort-explorer-frontend/nginx.conf"

  build_and_push "cohort-explorer-frontend" "$WORKDIR/cohort-explorer-frontend" \
    --build-arg ENVIRONMENT=deploy
fi

# ── ehrsuction ────────────────────────────────────────────────────────────────
if should_build "ehrsuction"; then
  echo "Cloning EHRsuction..."
  git clone --depth 1 https://github.com/SevKohler/EHRsuction \
    "$WORKDIR/EHRsuction"

  EHRSUCTION_CLIENT="$WORKDIR/EHRsuction/EHRSuctionClient.py"

  echo "Applying temporary EHRbase AQL compatibility patch to EHRsuction..."

  # Patch 1: capitalise COMPOSITION keyword (idempotent).
  sed -i 's/CONTAINS Composition c/CONTAINS COMPOSITION c/g' "$EHRSUCTION_CLIENT"

  # Patch 2: add EHRbase-specific ORDER BY column to request_canonical().
  if grep -q 'SELECT e/ehr_id/value, c, c/context/start_time/value' "$EHRSUCTION_CLIENT"; then
    echo "  EHRbase ORDER BY patch already present."
  else
    perl -0777 -i -pe \
      's{([ ]{12}aql = \(\n[ ]{16}"SELECT e/ehr_id/value, c FROM EHR e CONTAINS COMPOSITION c "\n[ ]{16}"ORDER BY c/context/start_time/value LIMIT \{\} OFFSET \{\}"\n[ ]{12}\)\.format\(limit, offset\)\n)}{            if self.platform == Platforms.EHRBASE:\n                aql = (\n                    "SELECT e/ehr_id/value, c, c/context/start_time/value "\n                    "FROM EHR e CONTAINS COMPOSITION c "\n                    "ORDER BY c/context/start_time/value LIMIT {} OFFSET {}"\n                ).format(limit, offset)\n            else:\n                aql = (\n                    "SELECT e/ehr_id/value, c FROM EHR e CONTAINS COMPOSITION c "\n                    "ORDER BY c/context/start_time/value LIMIT {} OFFSET {}"\n                ).format(limit, offset)\n}' \
      "$EHRSUCTION_CLIENT" \
    || { echo "ERROR: Could not apply EHRbase ORDER BY patch - upstream changed; inspect request_canonical()." >&2; exit 1; }
    grep -q 'SELECT e/ehr_id/value, c, c/context/start_time/value' "$EHRSUCTION_CLIENT" \
      || { echo "ERROR: ORDER BY patch did not apply - pattern not found." >&2; exit 1; }
  fi

  # Patch 3: use platform-aware AQL for count_ehrs().
  if grep -q 'SELECT COUNT(e/ehr_id/value) FROM EHR e' "$EHRSUCTION_CLIENT"; then
    echo "  EHRbase COUNT(ehr_id) patch already present."
  else
    perl -0777 -i -pe \
      's{([ ]{8}response = self\.session\.post\(\n[ ]{12}self\.query_endpoint,\n[ ]{12}headers=self\.headers,\n[ ]{12}json=\{"q": "SELECT COUNT\(e\) FROM EHR e"\},\n[ ]{12}auth=self\.auth,\n[ ]{12}verify=False  # This disables SSL verification\n[ ]{8}\)\n)}{        aql = (\n            "SELECT COUNT(e/ehr_id/value) FROM EHR e"\n            if self.platform == Platforms.EHRBASE\n            else "SELECT COUNT(e) FROM EHR e"\n        )\n        response = self.session.post(\n            self.query_endpoint,\n            headers=self.headers,\n            json={"q": aql},\n            auth=self.auth,\n            verify=False  # This disables SSL verification\n        )\n}' \
      "$EHRSUCTION_CLIENT" \
    || { echo "ERROR: Could not apply EHRbase COUNT patch - upstream changed; inspect count_ehrs()." >&2; exit 1; }
    grep -q 'SELECT COUNT(e/ehr_id/value) FROM EHR e' "$EHRSUCTION_CLIENT" \
      || { echo "ERROR: COUNT patch did not apply - pattern not found." >&2; exit 1; }
  fi

  echo "EHRsuction patch applied."
  build_and_push "ehrsuction" "$WORKDIR/EHRsuction"
fi

# ── openehrtool-backend ───────────────────────────────────────────────────────
if should_build "openehrtool-backend"; then
  # Clone only if not already cloned (shared repo with frontend)
  if [[ ! -d "$WORKDIR/openEHRTool-v2" ]]; then
    echo "Cloning openEHRTool-v2..."
    git clone --depth 1 https://github.com/crs4/openEHRTool-v2 \
      "$WORKDIR/openEHRTool-v2"
  fi

  # Required patch: expose SECRET_KEY via environment variable.
  # Upstream hardcodes it as a string literal; this is the only change we make.
  CONFIG_PY="$WORKDIR/openEHRTool-v2/backend-fastapi/app/config.py"
  if grep -q '"The Last of Us"' "$CONFIG_PY"; then
    echo "Applying SECRET_KEY patch to config.py..."
    # Ensure 'import os' is present
    if ! grep -q "^import os" "$CONFIG_PY"; then
      sed -i '1s/^/import os\n/' "$CONFIG_PY"
    fi
    sed -i 's/SECRET_KEY = "The Last of Us"/SECRET_KEY = os.environ.get("OPENEHRTOOL_SECRET_KEY", "change-me-in-production")/' \
      "$CONFIG_PY"
    echo "Patch applied."
  else
    echo "SECRET_KEY patch already applied or upstream changed – verify $CONFIG_PY manually."
  fi

  # Patch 2: start page figures via AQL aggregates. Upstream fetches one row per
  # composition and counts in Python - on the full repository EHRbase ran out of
  # heap, and behind the AQL default limit the figures stopped at 200,000.
  DASHBOARD_PATCH="$SCRIPT_DIR/patches/openehrtool-dashboard-aggregates.patch"
  if git -C "$WORKDIR/openEHRTool-v2" apply --reverse --check "$DASHBOARD_PATCH" 2>/dev/null; then
    echo "Dashboard patch already applied."
  elif git -C "$WORKDIR/openEHRTool-v2" apply --check "$DASHBOARD_PATCH"; then
    git -C "$WORKDIR/openEHRTool-v2" apply "$DASHBOARD_PATCH"
    echo "Dashboard patch applied."
  else
    echo "ERROR: dashboard patch does not apply - upstream changed" \
         "backend-fastapi/app/backend_ehrbase/dashboard/dashboard.py; update $DASHBOARD_PATCH." >&2
    exit 1
  fi

  build_and_push "openehrtool-backend" \
    "$WORKDIR/openEHRTool-v2/backend-fastapi"
fi

# ── openehrtool-frontend ──────────────────────────────────────────────────────
if should_build "openehrtool-frontend"; then
  if [[ -z "${OPENEHRTOOL_BACKEND_HOSTNAME:-}" ]]; then
    echo ""
    echo "Error: OPENEHRTOOL_BACKEND_HOSTNAME must be set to build the frontend image." >&2
    echo "  The backend hostname is baked into the Vue/Vite JS bundle at build time." >&2
    echo "  The value is host[:port] and may carry a path prefix." >&2
    echo "  Local dev (kubectl port-forward, set OPENEHRTOOL_BASE_PATH=/ as well):" >&2
    echo "    OPENEHRTOOL_BACKEND_HOSTNAME=localhost:5000 bash build-images.sh ..." >&2
    echo "  Behind the gateway, backend reachable under a path prefix:" >&2
    echo "    OPENEHRTOOL_BACKEND_HOSTNAME=ohs.example.org/openehrtool-api bash build-images.sh ..." >&2
    echo ""
    exit 1
  fi

  if [[ ! -d "$WORKDIR/openEHRTool-v2" ]]; then
    echo "Cloning openEHRTool-v2..."
    git clone --depth 1 https://github.com/crs4/openEHRTool-v2 \
      "$WORKDIR/openEHRTool-v2"
  fi

  # Run as non-root: switch the runtime stage to nginx-unprivileged (uid 101) and
  # serve on 8080 (non-root cannot bind <1024). The base image's stock nginx.conf
  # already points pid/logs at writable paths; only the server block needs the port.
  sed -i 's|FROM nginx:1\.28\.0-alpine|FROM nginxinc/nginx-unprivileged:1.28.0-alpine|' "$WORKDIR/openEHRTool-v2/frontend-vue/Dockerfile"
  sed -i 's|EXPOSE 80|EXPOSE 8080|' "$WORKDIR/openEHRTool-v2/frontend-vue/Dockerfile"
  sed -i 's|listen 80;|listen 8080;|' "$WORKDIR/openEHRTool-v2/frontend-vue/nginx.conf"

  # ── Subpath operation behind the gateway (https://<host>/openehrtool/) ──────
  # Two build-time patches; set OPENEHRTOOL_BASE_PATH=/ to build for the root
  # (local dev via port-forward).
  BASE_PATH="${OPENEHRTOOL_BASE_PATH:-/openehrtool/}"
  VITE_CONFIG="$WORKDIR/openEHRTool-v2/frontend-vue/vite.config.js"
  FE_SRC="$WORKDIR/openEHRTool-v2/frontend-vue/src"

  # 1. Vite must emit asset URLs under the prefix. Without this the bundle asks
  #    for /assets/... which the gateway routes to the Cohort Explorer frontend.
  if grep -q "base: '/'," "$VITE_CONFIG"; then
    sed -i "s|base: '/',|base: '${BASE_PATH}',|" "$VITE_CONFIG"
    echo "Vite base set to ${BASE_PATH}."
  elif grep -q "base: '${BASE_PATH}'," "$VITE_CONFIG"; then
    echo "Vite base already set to ${BASE_PATH}."
  else
    echo "Error: cannot set the Vite base path, upstream vite.config.js changed:" >&2
    grep -n "base:" "$VITE_CONFIG" >&2
    exit 1
  fi

  # 2. src/config.js exports only host[:port]; the call sites prepend a hard
  #    http://. On an HTTPS page the browser blocks that as mixed content, so
  #    make the URLs protocol-relative.
  if grep -rqF 'http://${BACKEND_HOST}' "$FE_SRC"; then
    grep -rlF 'http://${BACKEND_HOST}' "$FE_SRC" \
      | xargs sed -i 's|http://\${BACKEND_HOST}|//${BACKEND_HOST}|g'
    echo "Backend URLs switched to protocol-relative."
  elif grep -rqF '//${BACKEND_HOST}' "$FE_SRC"; then
    echo "Backend URLs already protocol-relative."
  else
    echo "Error: found no 'http://\${BACKEND_HOST}' to patch - upstream composes" >&2
    echo "  the backend URL differently. Occurrences of BACKEND_HOST:" >&2
    grep -rn "BACKEND_HOST" "$FE_SRC" >&2
    exit 1
  fi

  build_and_push "openehrtool-frontend" \
    "$WORKDIR/openEHRTool-v2/frontend-vue" \
    --build-arg "VITE_BACKEND_HOSTNAME=${OPENEHRTOOL_BACKEND_HOSTNAME}"
fi

echo "Done."
echo ""
echo "Update values.yaml image repositories to point to: ${REGISTRY}/<name>:${TAG}"
