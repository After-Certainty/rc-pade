#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/004-coder-workspace"
GENERATED="$EXPERIMENT/generated"
WORK="${RC_PADE_EXPERIMENT_WORK:-$ROOT/.work/experiment-004}"
PADE_TAG="v0.2.1"
PADE_COMMIT="d50174a2696743db3879dc98615801f5ad8d462a"
PADE_REPO="https://github.com/After-Certainty/pade.git"
PADE="$WORK/src/pade"
RC_CHAIN="$WORK/rc-chain"
EXPECTED_PADE="$ROOT/experiments/002-real-rc-profile/expected-pade.yaml"

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return 0
  fi

  echo "Go not found on PATH; bootstrapping mise + Go from mise.toml (ordinary toolchain setup)." >&2

  if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
    export PATH="${HOME}/.local/bin:${PATH}"
  fi

  if ! command -v mise >/dev/null 2>&1; then
    echo "mise install failed; install Go 1.26.6 (see mise.toml) and re-run." >&2
    exit 1
  fi

  (
    cd "$ROOT"
    mise install
  )
  eval "$(mise activate bash --shims)"

  if ! command -v go >/dev/null 2>&1; then
    echo "Go still missing after mise install; install Go 1.26.6 and re-run." >&2
    exit 1
  fi
}

# Resolve a concrete Go binary so nested checkouts (e.g. PADE) with untrusted
# mise.toml files cannot intercept `go` via shims.
resolve_go_bin() {
  if command -v mise >/dev/null 2>&1; then
    local mise_go
    mise_go="$(cd "$ROOT" && mise which go 2>/dev/null || true)"
    if [[ -n "$mise_go" && -x "$mise_go" ]]; then
      printf '%s\n' "$mise_go"
      return 0
    fi
  fi
  command -v go
}

for command in git python3 diff cmp curl; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 1; }
done

ensure_go
GO_BIN="$(resolve_go_bin)"

rm -rf "$WORK" "$GENERATED"
mkdir -p "$WORK/src" "$GENERATED"

{
  echo "hostname=$(hostname)"
  echo "pwd=$(pwd)"
  echo "uname=$(uname -srm)"
  echo "CODER=${CODER:-}"
  echo "CODER_WORKSPACE_NAME=${CODER_WORKSPACE_NAME:-}"
  echo "CODER_WORKSPACE_AGENT_NAME=${CODER_WORKSPACE_AGENT_NAME:-}"
  echo "CODER_WORKSPACE_OWNER_NAME=${CODER_WORKSPACE_OWNER_NAME:-}"
  echo "go=$("$GO_BIN" version)"
  echo "python3=$(python3 --version 2>&1)"
  echo "rc_pade_commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "rc_pade_branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  echo "pade_tag=${PADE_TAG}"
  echo "pade_commit=${PADE_COMMIT}"
  echo "runtime_conditions_sdk=2b54b1230afc6075986b888701ef1b5c91c9ec4b"
  echo "runtime_conditions_extensions=e4c228ebab54c294783059772e973a665fc5f3f5"
  echo "runtime_conditions_profiler=3c882dbc7427f4c13bd127bc13069e11fc548e67"
  echo "fixture_source=experiments/003-source-to-session/app/storage.py"
  echo "projection_policy=examples/s3-put-object/policy.yaml"
} > "$GENERATED/environment.txt"

echo "Running Experiment 003 source→RC→rc-pade chain inside this workspace..."
# Ensure Exp 003's `go run` also uses a concrete binary under mise shims.
export PATH="$(dirname "$GO_BIN"):${PATH}"
RC_PADE_EXPERIMENT_WORK="$RC_CHAIN" \
  bash "$ROOT/experiments/003-source-to-session/run.sh"

cp "$RC_CHAIN/generated-runtime-conditions.yaml" "$GENERATED/runtime-conditions.yaml"
cp "$RC_CHAIN/generated-pade.yaml" "$GENERATED/development-session.yaml"

diff -u "$EXPECTED_PADE" "$GENERATED/development-session.yaml"

echo "Cloning PADE ${PADE_TAG}..."
git clone --quiet --branch "$PADE_TAG" --depth 1 "$PADE_REPO" "$PADE"
RESOLVED_PADE_COMMIT="$(git -C "$PADE" rev-parse HEAD)"
if [[ "$RESOLVED_PADE_COMMIT" != "$PADE_COMMIT" ]]; then
  echo "PADE commit mismatch: expected ${PADE_COMMIT}, got ${RESOLVED_PADE_COMMIT}" >&2
  exit 1
fi
echo "pade_resolved_commit=${RESOLVED_PADE_COMMIT}" >> "$GENERATED/environment.txt"

echo "Validating generated DevelopmentSession with PADE..."
(
  cd "$PADE"
  "$GO_BIN" run ./cmd/pade validate -f "$GENERATED/development-session.yaml"
)

echo "Planning generated DevelopmentSession with PADE..."
(
  cd "$PADE"
  "$GO_BIN" run ./cmd/pade plan -f "$GENERATED/development-session.yaml"
) | tee "$GENERATED/pade-plan.txt"

grep -q 'aws.s3.bucket.write' "$GENERATED/pade-plan.txt"
grep -q 'PutObject' "$GENERATED/runtime-conditions.yaml"

printf 'Experiment 004 passed.\nGenerated RC profile: %s\nGenerated PADE session: %s\nPADE plan: %s\nEnvironment: %s\n' \
  "$GENERATED/runtime-conditions.yaml" \
  "$GENERATED/development-session.yaml" \
  "$GENERATED/pade-plan.txt" \
  "$GENERATED/environment.txt"
