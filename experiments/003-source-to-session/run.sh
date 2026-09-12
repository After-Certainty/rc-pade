#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/003-source-to-session"
WORK="${RC_PADE_EXPERIMENT_WORK:-$ROOT/.work/experiment-003}"

SDK_SHA="2b54b1230afc6075986b888701ef1b5c91c9ec4b"
EXTENSIONS_SHA="e4c228ebab54c294783059772e973a665fc5f3f5"
PROFILER_SHA="3c882dbc7427f4c13bd127bc13069e11fc548e67"

SDK="$WORK/src/sdk-authorship-discovery"
EXTENSIONS="$WORK/src/extensions"
PROFILER="$WORK/src/python-rc-profiler"
RC_OUTPUT="$WORK/rc-maintenance"
GENERATED_RC="$WORK/generated-runtime-conditions.yaml"
GENERATED_PADE="$WORK/generated-pade.yaml"

for command in git python3 go diff cmp; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/src"

clone_at() {
  local repository="$1"
  local revision="$2"
  local destination="$3"
  git clone --quiet "$repository" "$destination"
  git -C "$destination" checkout --quiet --detach "$revision"
}

clone_at https://github.com/runtimeconditions/sdk-authorship-discovery.git "$SDK_SHA" "$SDK"
clone_at https://github.com/runtimeconditions/extensions.git "$EXTENSIONS_SHA" "$EXTENSIONS"
clone_at https://github.com/runtimeconditions/python-rc-profiler.git "$PROFILER_SHA" "$PROFILER"

# The inspected fixture in this repository must remain byte-identical to the
# application source actually consumed from the pinned Runtime Conditions repo.
cmp \
  "$EXPERIMENT/app/storage.py" \
  "$SDK/s3/python/direct-client/src/s3_direct_client/storage.py"

python3 -m venv "$WORK/venv"
# shellcheck disable=SC1091
source "$WORK/venv/bin/activate"
python -m pip install --disable-pip-version-check --quiet --upgrade pip
python -m pip install --disable-pip-version-check --quiet \
  -r "$SDK/authorship/aws-python/requirements.txt"
python -m pip install --disable-pip-version-check --quiet -e "$PROFILER"

python "$SDK/authorship/aws-python/tools/run_release_maintenance.py" \
  --experiment "$SDK/maintenance/aws-python-s3/experiment.yaml" \
  --release-file "$EXPERIMENT/release.yaml" \
  --extensions-root "$EXTENSIONS" \
  --profiler-root "$PROFILER" \
  --source-cache "$WORK/source-cache" \
  --work-root "$WORK/maintenance-work" \
  --output "$RC_OUTPUT"

cp "$RC_OUTPUT/artifacts/profiles/direct-client.yaml" "$GENERATED_RC"

go run "$ROOT/cmd/rc-pade" generate \
  --profile "$GENERATED_RC" \
  --policy "$ROOT/examples/s3-put-object/policy.yaml" \
  > "$GENERATED_PADE"

diff -u \
  "$ROOT/experiments/002-real-rc-profile/expected-pade.yaml" \
  "$GENERATED_PADE"

printf 'Experiment 003 passed.\nGenerated RC profile: %s\nGenerated PADE session: %s\n' \
  "$GENERATED_RC" "$GENERATED_PADE"
