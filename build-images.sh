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
# a JDK 17 container — no host JDK or Maven required.
if should_build "cohort-explorer-backend"; then
  echo "Cloning cohort-explorer-backend..."
  git clone --depth 1 https://github.com/highmed/cohort-explorer-backend \
    "$WORKDIR/cohort-explorer-backend"

  # Generate a multi-stage Dockerfile: compile with JDK 17, run with JRE 17.
  cat > "$WORKDIR/cohort-explorer-backend/Dockerfile" << 'DOCKEREOF'
FROM maven:3.9-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY . .
RUN mvn package -Dmaven.test.skip=true --no-transfer-progress

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
    || { echo "ERROR: Could not apply EHRbase ORDER BY patch — upstream changed; inspect request_canonical()." >&2; exit 1; }
    grep -q 'SELECT e/ehr_id/value, c, c/context/start_time/value' "$EHRSUCTION_CLIENT" \
      || { echo "ERROR: ORDER BY patch did not apply — pattern not found." >&2; exit 1; }
  fi

  # Patch 3: use platform-aware AQL for count_ehrs().
  if grep -q 'SELECT COUNT(e/ehr_id/value) FROM EHR e' "$EHRSUCTION_CLIENT"; then
    echo "  EHRbase COUNT(ehr_id) patch already present."
  else
    perl -0777 -i -pe \
      's{([ ]{8}response = self\.session\.post\(\n[ ]{12}self\.query_endpoint,\n[ ]{12}headers=self\.headers,\n[ ]{12}json=\{"q": "SELECT COUNT\(e\) FROM EHR e"\},\n[ ]{12}auth=self\.auth,\n[ ]{12}verify=False  # This disables SSL verification\n[ ]{8}\)\n)}{        aql = (\n            "SELECT COUNT(e/ehr_id/value) FROM EHR e"\n            if self.platform == Platforms.EHRBASE\n            else "SELECT COUNT(e) FROM EHR e"\n        )\n        response = self.session.post(\n            self.query_endpoint,\n            headers=self.headers,\n            json={"q": aql},\n            auth=self.auth,\n            verify=False  # This disables SSL verification\n        )\n}' \
      "$EHRSUCTION_CLIENT" \
    || { echo "ERROR: Could not apply EHRbase COUNT patch — upstream changed; inspect count_ehrs()." >&2; exit 1; }
    grep -q 'SELECT COUNT(e/ehr_id/value) FROM EHR e' "$EHRSUCTION_CLIENT" \
      || { echo "ERROR: COUNT patch did not apply — pattern not found." >&2; exit 1; }
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

  build_and_push "openehrtool-backend" \
    "$WORKDIR/openEHRTool-v2/backend-fastapi"
fi

# ── openehrtool-frontend ──────────────────────────────────────────────────────
if should_build "openehrtool-frontend"; then
  if [[ -z "${OPENEHRTOOL_BACKEND_HOSTNAME:-}" ]]; then
    echo ""
    echo "Error: OPENEHRTOOL_BACKEND_HOSTNAME must be set to build the frontend image." >&2
    echo "  The backend hostname is baked into the Vue/Vite JS bundle at build time." >&2
    echo "  Local dev (kubectl port-forward):" >&2
    echo "    OPENEHRTOOL_BACKEND_HOSTNAME=localhost bash build-images.sh ..." >&2
    echo "  Production:" >&2
    echo "    OPENEHRTOOL_BACKEND_HOSTNAME=openehrtool-api.ohs.example.org bash build-images.sh ..." >&2
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

  build_and_push "openehrtool-frontend" \
    "$WORKDIR/openEHRTool-v2/frontend-vue" \
    --build-arg "VITE_BACKEND_HOSTNAME=${OPENEHRTOOL_BACKEND_HOSTNAME}"
fi

echo "Done."
echo ""
echo "Update values.yaml image repositories to point to: ${REGISTRY}/<name>:${TAG}"
