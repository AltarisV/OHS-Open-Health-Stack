#!/usr/bin/env bash
# local-up.sh - brings up the whole Open Health Stack on Docker Desktop Kubernetes
# from a fresh clone, in one command.
#
#   bash scripts/local-up.sh
#
# Covers every step of the manual quick start: prerequisite checks, the two
# database operators, the namespace, a .env with generated credentials, the
# self-hosted images, the Helm release, and the Athena vocabulary. Safe to re-run -
# every phase checks whether its work is already done and skips it.
#
# Options:
#   -n, --namespace NAME   target namespace (default: ohs)
#       --context NAME     require this kube-context (default: docker-desktop)
#       --skip-images      do not build images (they must already exist)
#       --rebuild-images   rebuild even if the images are present
#       --skip-vocab       do not load the Athena vocabulary
#       --full-vocab       load all vocabulary tables, not just the core five
#   -y, --yes              do not ask for confirmation
#   -h, --help             this text
#
# What it deliberately does NOT do:
#   - install docker/kubectl/helm, or enable Kubernetes in Docker Desktop
#   - download the Athena vocabulary (it is licence-gated; see --skip-vocab note)
#   - push images anywhere (Docker Desktop shares the host daemon, no registry needed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="ohs"
REQUIRE_CONTEXT="docker-desktop"
SKIP_IMAGES=false
REBUILD_IMAGES=false
SKIP_VOCAB=false
FULL_VOCAB=false
ASSUME_YES=false

REGISTRY="localhost:5000"
TAG="ohs"
COMPONENTS=(cohort-explorer-backend cohort-explorer-frontend ehrsuction
            openehrtool-backend openehrtool-frontend)

# ── Output helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; D=""; N=""
fi
PHASE=0
phase() { PHASE=$((PHASE + 1)); printf '\n%s[%d/8] %s%s\n' "$B" "$PHASE" "$1" "$N"; }
ok()    { printf '  %s+%s %s\n' "$G" "$N" "$1"; }
skip()  { printf '  %s=%s %s\n' "$D" "$N" "$1"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
die()   { printf '\n%sError:%s %s\n' "$R" "$N" "$1" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)   NAMESPACE="$2"; shift 2 ;;
    --context)        REQUIRE_CONTEXT="$2"; shift 2 ;;
    --skip-images)    SKIP_IMAGES=true; shift ;;
    --rebuild-images) REBUILD_IMAGES=true; shift ;;
    --skip-vocab)     SKIP_VOCAB=true; shift ;;
    --full-vocab)     FULL_VOCAB=true; shift ;;
    -y|--yes)         ASSUME_YES=true; shift ;;
    -h|--help)        sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
done

cd "$REPO_ROOT"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
# Everything that can be known before touching the cluster is checked here, so a
# run fails in the first seconds rather than four minutes into an image build.
phase "Preflight"

for tool in docker kubectl helm git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found on PATH."
done
ok "docker, kubectl, helm, git present"

docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop and retry."
ok "docker daemon reachable"

# build-images.sh applies its source patches with python3. Windows ships an
# App-Execution-Alias at ...\WindowsApps\python3 that only prints "Python was not
# found" and exits non-zero, so `command -v python3` succeeds on machines that
# have no Python at all - the script would then fail minutes later, mid-build.
# Hence: run it, do not merely locate it. Where only 'python' works, a shim costs
# nothing and removes the whole class of failure; nothing outside this run sees it.
py_works() { "$1" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; }

SHIM_DIR=""
if ! py_works python3; then
  if py_works python; then
    SHIM_DIR="$(mktemp -d)"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$(command -v python)" > "$SHIM_DIR/python3"
    chmod +x "$SHIM_DIR/python3"
    export PATH="$SHIM_DIR:$PATH"
    trap 'rm -rf "$SHIM_DIR"' EXIT
    ok "python3 shim created ('python3' missing or non-functional, 'python' works)"
  elif [[ "$SKIP_IMAGES" == false ]]; then
    die "No working Python 3 - scripts/build-images.sh needs it to patch sources.
  A 'python3' on PATH that only prints \"Python was not found\" is the Windows
  App-Execution-Alias, not an interpreter: install Python 3 (and untick the
  aliases under Settings > Apps > Advanced app settings > App execution aliases),
  or pass --skip-images if the images already exist."
  else
    warn "no working Python 3 (fine, images are skipped)"
  fi
else
  ok "python3 present"
fi

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[[ -n "$CONTEXT" ]] || die "No current kube-context. Enable Kubernetes in Docker Desktop."
if [[ -n "$REQUIRE_CONTEXT" && "$CONTEXT" != "$REQUIRE_CONTEXT" ]]; then
  die "Current kube-context is '$CONTEXT', expected '$REQUIRE_CONTEXT'.
  This script deploys into whatever cluster the context points at - refusing to
  guess. Pass --context '$CONTEXT' if that really is the target."
fi
kubectl get nodes >/dev/null 2>&1 \
  || die "Kubernetes API not reachable on context '$CONTEXT'.
  In Docker Desktop: Settings > Kubernetes > Enable Kubernetes."
ok "cluster reachable (context: $CONTEXT)"

if [[ "$ASSUME_YES" == false ]]; then
  printf '\n  About to deploy into %s%s%s on context %s%s%s.\n' "$B" "$NAMESPACE" "$N" "$B" "$CONTEXT" "$N"
  read -r -p "  Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }
fi

# ── 2. Operators ──────────────────────────────────────────────────────────────
# CloudNativePG and the MongoDB community operator live outside this chart and
# outside the target namespace; the chart's database resources are CRs they own,
# so they must exist before the release is installed.
phase "Database operators"

install_operator() {
  local release="$1" ns="$2" repo_name="$3" repo_url="$4" chart="$5"; shift 5
  if helm status "$release" -n "$ns" >/dev/null 2>&1; then
    skip "$release already installed in $ns"
    return
  fi
  helm repo add "$repo_name" "$repo_url" >/dev/null 2>&1 || true
  helm repo update "$repo_name" >/dev/null 2>&1 || helm repo update >/dev/null 2>&1
  helm install "$release" "$chart" -n "$ns" --create-namespace --wait --timeout 10m "$@" >/dev/null
  ok "$release installed in $ns"
}

install_operator cnpg-system cnpg-system \
  cnpg https://cloudnative-pg.github.io/charts cnpg/cloudnative-pg
install_operator mongodb-operator mongodb-operator \
  mongodb https://mongodb.github.io/helm-charts mongodb/community-operator \
  --set "operator.watchNamespace=$NAMESPACE"

# ── 3. Namespace ──────────────────────────────────────────────────────────────
phase "Namespace"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# The chart's NetworkPolicies select peer namespaces by this label; without it a
# policy-enabled deployment silently loses cross-namespace traffic.
kubectl label namespace "$NAMESPACE" "name=$NAMESPACE" --overwrite >/dev/null
ok "namespace $NAMESPACE ready (labelled name=$NAMESPACE)"

# ── 4. Credentials ────────────────────────────────────────────────────────────
# .env is gitignored, so a fresh clone has none. Generating it beats asking the
# user to invent fourteen passwords by hand, and generated values are better than
# the "change_me" placeholders that otherwise survive into a running cluster.
phase "Credentials"

randpw() {
  # Alphanumeric on purpose: these end up inside a MongoDB connection URI and
  # several postgres URLs, where '/', '+', '@' and ':' would need escaping.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
  fi
}

if [[ -f .env ]]; then
  skip ".env exists - leaving it untouched"
  missing=""
  while IFS= read -r key; do
    grep -qE "^${key}=" .env || missing="$missing $key"
  done < <(grep -oE '^[A-Z_]+' .env.example)
  if [[ -n "$missing" ]]; then
    warn "keys in .env.example but not in .env:$missing"
    warn "append them, or delete .env and re-run to regenerate"
  fi
else
  cp .env.example .env
  while IFS= read -r key; do
    # Deliberately left empty: an empty research password makes Keycloak assign a
    # random one, which is the documented behaviour for that optional user.
    [[ "$key" == "KEYCLOAK_RESEARCH_PASSWORD" ]] && continue
    pw="$(randpw)"
    # The delimiter is '|' because generated values never contain it.
    sed -i "s|^${key}=.*|${key}=${pw}|" .env
  done < <(grep -oE '^[A-Z_]+' .env.example)
  chmod 600 .env 2>/dev/null || true
  ok ".env generated with random credentials (gitignored)"
  warn "note the EHRbase password from .env - the test console and curl need it"
fi

bash scripts/create-secret.sh >/dev/null
ok "secrets applied in $NAMESPACE"

# ── 5. Images ─────────────────────────────────────────────────────────────────
# openEHRTool, EHRsuction and the Cohort Explorer have no published images.
# Docker Desktop shares the host daemon, so a local build with --skip-push is
# immediately visible to the cluster - no registry involved despite the name.
phase "Images"

if [[ "$SKIP_IMAGES" == true ]]; then
  skip "image build skipped (--skip-images)"
else
  to_build=()
  for c in "${COMPONENTS[@]}"; do
    if [[ "$REBUILD_IMAGES" == false ]] && docker image inspect "$REGISTRY/$c:$TAG" >/dev/null 2>&1; then
      skip "$c:$TAG present"
    else
      to_build+=("$c")
    fi
  done

  if [[ ${#to_build[@]} -eq 0 ]]; then
    ok "all images present (pass --rebuild-images to force)"
  else
    warn "building ${#to_build[@]} image(s) - this takes several minutes"
    for c in "${to_build[@]}"; do
      printf '  %s->%s %s\n' "$D" "$N" "$c"
      # The frontend bakes its backend host into the JS bundle at build time;
      # localhost is what the port-forward exposes.
      OPENEHRTOOL_BACKEND_HOSTNAME=localhost \
        bash scripts/build-images.sh --registry "$REGISTRY" --tag "$TAG" \
          --skip-push --component "$c" >/dev/null \
        || die "build of $c failed. Re-run it alone to see the output:
  OPENEHRTOOL_BACKEND_HOSTNAME=localhost bash scripts/build-images.sh \\
    --registry $REGISTRY --tag $TAG --skip-push --component $c"
      ok "$c built"
    done
  fi
fi

# ── 6. Helm release ───────────────────────────────────────────────────────────
phase "Helm release"
[[ -f values-local.yaml ]] || die "values-local.yaml missing - it carries the Docker Desktop overrides."
helm upgrade --install ohs . -f values.yaml -f values-local.yaml \
  -n "$NAMESPACE" --timeout 20m
ok "release ohs deployed ($(helm list -n "$NAMESPACE" -f '^ohs$' -o json | grep -o '"revision":"[0-9]*"' | head -1 | cut -d'"' -f4 | sed 's/^/revision /'))"

# ── 7. Wait for workloads ─────────────────────────────────────────────────────
# The databases are the slow part; on a first install the whole set can take
# 10-15 minutes, mostly CNPG initdb and the Keycloak realm import.
phase "Waiting for workloads"
deploys=$(kubectl get deploy -n "$NAMESPACE" -o name 2>/dev/null || true)
if [[ -z "$deploys" ]]; then
  warn "no deployments found yet"
else
  failed=""
  for d in $deploys; do
    if kubectl rollout status "$d" -n "$NAMESPACE" --timeout=15m >/dev/null 2>&1; then
      ok "${d#deployment.apps/}"
    else
      failed="$failed ${d#deployment.apps/}"
      warn "${d#deployment.apps/} not ready within 15m"
    fi
  done
  [[ -n "$failed" ]] && warn "check with: kubectl get pods -n $NAMESPACE"
fi

# ── 8. Vocabulary ─────────────────────────────────────────────────────────────
# Not cosmetic: the Eos person mapping falls back to concept id 0 whenever a
# composition carries no person data, and that row only exists once CONCEPT.csv
# is loaded. Without it POST /person fails outright with HTTP 500.
phase "Athena vocabulary (Eos)"

if [[ "$SKIP_VOCAB" == true ]]; then
  skip "vocabulary skipped (--skip-vocab)"
elif [[ ! -f vocab/CONCEPT.csv ]]; then
  warn "vocab/CONCEPT.csv not found - skipping."
  warn "Eos POST /person will fail with HTTP 500 until it is loaded."
  warn "Download the vocabularies from https://athena.ohdsi.org (free account,"
  warn "licence-gated, so this script cannot fetch them), unzip into vocab/, then:"
  warn "  bash scripts/load-vocab.sh"
else
  pg_pod=$(kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=postgres-cluster" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  concepts=""
  [[ -n "$pg_pod" ]] && concepts=$(kubectl exec -n "$NAMESPACE" "$pg_pod" -c postgres -- \
    psql -U postgres -d eos_omop -t -A -c "SELECT COUNT(*) FROM concept;" 2>/dev/null | tr -d ' \r\n' || true)

  if [[ "$concepts" =~ ^[0-9]+$ && "$concepts" -gt 0 ]]; then
    skip "vocabulary already loaded ($concepts concepts)"
  else
    vocab_dir="$REPO_ROOT/vocab"
    if [[ "$FULL_VOCAB" == false ]]; then
      # Only the five tables Eos actually dereferences. The other four are
      # 4.4 GB between them and matter only for drug/ingredient resolution, so
      # they are opt-in via --full-vocab. Hard links, not copies: same volume,
      # no extra disk. Falls back to the full directory if links are refused.
      core_dir="$REPO_ROOT/.vocab-core"
      rm -rf "$core_dir"; mkdir -p "$core_dir"
      linked=true
      for f in CONCEPT_CLASS.csv DOMAIN.csv VOCABULARY.csv RELATIONSHIP.csv CONCEPT.csv; do
        ln "vocab/$f" "$core_dir/$f" 2>/dev/null || { linked=false; break; }
      done
      if [[ "$linked" == true ]]; then
        vocab_dir="$core_dir"
        warn "loading core tables only (--full-vocab for all nine)"
      else
        rm -rf "$core_dir"
        warn "hard links unavailable - loading every table present in vocab/"
      fi
    fi
    NAMESPACE="$NAMESPACE" VOCAB_DIR="$vocab_dir" bash scripts/load-vocab.sh \
      || warn "vocabulary load failed - re-run: bash scripts/load-vocab.sh"
    rm -rf "$REPO_ROOT/.vocab-core"
    kubectl rollout restart deployment -n "$NAMESPACE" -l app=eos >/dev/null 2>&1 || true
    ok "vocabulary loaded, Eos restarted"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n%sStack is up in namespace %s.%s\n\n' "$B" "$NAMESPACE" "$N"
printf 'Next:\n'
printf '  bash scripts/port-forward.sh %s        # forward every service\n' "$NAMESPACE"
printf '  python scripts/test-ui-proxy.py       # then http://localhost:8888/test-ui/\n\n'
printf 'Check:\n'
printf '  kubectl get pods -n %s\n' "$NAMESPACE"
printf '  helm status ohs -n %s\n\n' "$NAMESPACE"
printf 'EHRbase credentials are in .env (EHRBASE_USER_PASSWORD).\n'
