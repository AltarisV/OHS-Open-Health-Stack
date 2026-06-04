#!/usr/bin/env bash
# Builds and pushes self-hosted images required by OHS.
# Repos are cloned into a temporary directory.
#
# Usage:
#   bash build-images.sh [--registry <host:port>] [--tag <tag>] [--skip-push] [--component <name>]
#
# Components: cohort-explorer-backend, cohort-explorer-frontend,
#             openehrtool-backend, openehrtool-frontend
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
# No Dockerfile – uses Spring Boot Buildpacks via 'mvn spring-boot:build-image'.
# Requires: JDK 17, Maven on PATH.
if should_build "cohort-explorer-backend"; then
  if ! command -v mvn &>/dev/null; then
    echo "Error: 'mvn' not found. Install Maven + JDK 17 to build cohort-explorer-backend." >&2
    exit 1
  fi
  echo "Cloning cohort-explorer-backend..."
  git clone --depth 1 https://github.com/highmed/cohort-explorer-backend \
    "$WORKDIR/cohort-explorer-backend"

  FULL_IMAGE="${REGISTRY}/cohort-explorer-backend:${TAG}"
  echo "──────────────────────────────────────────"
  echo "Building: $FULL_IMAGE  (spring-boot:build-image)"
  pushd "$WORKDIR/cohort-explorer-backend" >/dev/null
  mvn spring-boot:build-image \
    -Dspring-boot.build-image.imageName="$FULL_IMAGE" \
    -DskipTests
  popd >/dev/null

  if [[ "$SKIP_PUSH" == false ]]; then
    echo "Pushing:  $FULL_IMAGE"
    docker push "$FULL_IMAGE"
  else
    echo "Skipping push (--skip-push)"
  fi
  echo ""
fi

# ── cohort-explorer-frontend ──────────────────────────────────────────────────
if should_build "cohort-explorer-frontend"; then
  echo "Cloning cohort-explorer-frontend..."
  git clone --depth 1 https://github.com/highmed/cohort-explorer-frontend \
    "$WORKDIR/cohort-explorer-frontend"

  build_and_push "cohort-explorer-frontend" "$WORKDIR/cohort-explorer-frontend" \
    --build-arg ENVIRONMENT=deploy
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
    echo "  Example:" >&2
    echo "    OPENEHRTOOL_BACKEND_HOSTNAME=openehrtool-api.ohs.example.org bash build-images.sh ..." >&2
    echo ""
    exit 1
  fi

  if [[ ! -d "$WORKDIR/openEHRTool-v2" ]]; then
    echo "Cloning openEHRTool-v2..."
    git clone --depth 1 https://github.com/crs4/openEHRTool-v2 \
      "$WORKDIR/openEHRTool-v2"
  fi

  build_and_push "openehrtool-frontend" \
    "$WORKDIR/openEHRTool-v2/frontend-vue" \
    --build-arg "VITE_BACKEND_HOSTNAME=${OPENEHRTOOL_BACKEND_HOSTNAME}"
fi

echo "Done."
echo ""
echo "Update values.yaml image repositories to point to: ${REGISTRY}/<name>:${TAG}"
