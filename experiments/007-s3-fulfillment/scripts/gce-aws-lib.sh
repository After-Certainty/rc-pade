#!/usr/bin/env bash
# Shared helpers for the Experiment 007 Phase 2 GCE -> AWS scripts. Source, do
# not execute. Never reads credential values; only checks presence.
set -euo pipefail

GCE_AWS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GCE_AWS_VENV="${RC_PADE_007_VENV:-$GCE_AWS_ROOT/.work/experiment-007-gce-aws/venv}"
# Versions already recorded in Experiment 007 provenance (awsSdk).
GCE_AWS_PIP_PINS=(boto3==1.43.80 botocore==1.43.80 s3transfer==0.19.2)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Refuses if any static AWS credential configuration is present. Prints names
# only, never values.
gce_aws_refuse_ambient_credentials() {
  local name present=()
  for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_PROFILE; do
    if [[ -n "${!name+x}" ]]; then
      present+=("$name")
    fi
  done
  if ((${#present[@]} > 0)); then
    die "static AWS credential configuration is present (${present[*]}); unset it before running the federation proof"
  fi
}

gce_aws_ensure_venv() {
  if [[ ! -x "$GCE_AWS_VENV/bin/python" ]]; then
    printf 'creating venv %s\n' "$GCE_AWS_VENV" >&2
    python3 -m venv "$GCE_AWS_VENV"
  fi
  if ! "$GCE_AWS_VENV/bin/python" - "${GCE_AWS_PIP_PINS[@]}" <<'PY' 2>/dev/null; then
import sys
from importlib.metadata import version
for pin in sys.argv[1:]:
    name, want = pin.split("==")
    if version(name) != want:
        sys.exit(1)
PY
    "$GCE_AWS_VENV/bin/python" -m pip install --disable-pip-version-check --quiet "${GCE_AWS_PIP_PINS[@]}"
  fi
}
