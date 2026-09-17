#!/usr/bin/env bash
# Experiment 008 — compose the real rc-demos Profile (same pins as 006) and
# project source_control/git via opaque fields + bounded field matcher.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/008-rc-field-projection"
GENERATED="$EXPERIMENT/generated"
WORK="${RC_PADE_EXPERIMENT_WORK:-$ROOT/.work/experiment-008}"
SIBLINGS="$WORK/siblings"

# Overrideable pins. Defaults match Experiment 006 provenance exactly.
RC_DEMOS_REPO="${RC_DEMOS_REPO:-https://github.com/ksteffe/rc-demos.git}"
RC_DEMOS_REF="${RC_DEMOS_REF:-13a85bd4221797c94e209fad576a9d4ab89522f3}"
EXTENSIONS_REPO="${EXTENSIONS_REPO:-https://github.com/runtimeconditions/extensions.git}"
EXTENSIONS_REF="${EXTENSIONS_REF:-7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7}"
PROFILER_REPO="${PROFILER_REPO:-https://github.com/runtimeconditions/go-rc-profiler.git}"
PROFILER_REF="${PROFILER_REF:-5d2e860e48842b89ec83414123a7e59228f61d36}"
POLICY="${RC_PADE_POLICY:-$EXPERIMENT/policy.yaml}"
KEEP_WORK="${RC_PADE_KEEP_WORK:-0}"

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

for command in git; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 1; }
done

if ! command -v go >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
  (cd "$ROOT" && mise install)
  eval "$(mise activate bash --shims)" || true
fi
GO_BIN="$(resolve_go_bin)"
[[ -x "$GO_BIN" ]] || { echo "Go not found; install Go (see mise.toml) and re-run." >&2; exit 1; }
export PATH="$(dirname "$GO_BIN"):${PATH}"

cleanup() {
  if [[ "$KEEP_WORK" != "1" ]]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

rm -rf "$WORK" "$GENERATED"
mkdir -p "$SIBLINGS" "$GENERATED" "$WORK/tmp"

clone_repo() {
  local repository="$1"
  local destination="$2"
  local ref="${3:-}"
  git clone --quiet "$repository" "$destination"
  if [[ -n "$ref" ]]; then
    git -C "$destination" checkout --quiet --detach "$ref"
  fi
}

echo "Cloning sibling workspace under $SIBLINGS ..."
clone_repo "$RC_DEMOS_REPO" "$SIBLINGS/rc-demos" "$RC_DEMOS_REF"
clone_repo "$EXTENSIONS_REPO" "$SIBLINGS/extensions" "$EXTENSIONS_REF"
clone_repo "$PROFILER_REPO" "$SIBLINGS/go-rc-profiler" "$PROFILER_REF"

RC_DEMOS_SHA="$(git -C "$SIBLINGS/rc-demos" rev-parse HEAD)"
EXTENSIONS_SHA="$(git -C "$SIBLINGS/extensions" rev-parse HEAD)"
PROFILER_SHA="$(git -C "$SIBLINGS/go-rc-profiler" rev-parse HEAD)"
RC_PADE_SHA="$(git -C "$ROOT" rev-parse HEAD)"

DEMO_ROOT="$SIBLINGS/rc-demos/dev-container-profile"
[[ -d "$DEMO_ROOT" ]] || { echo "missing demo root: $DEMO_ROOT" >&2; exit 1; }
[[ -f "$DEMO_ROOT/scripts/compose-dev-container-profile.sh" ]] || {
  echo "missing compose script" >&2
  exit 1
}

{
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "rc_pade_commit=${RC_PADE_SHA}"
  echo "rc_pade_branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  echo "rc_demos_repo=${RC_DEMOS_REPO}"
  echo "rc_demos_ref_requested=${RC_DEMOS_REF}"
  echo "rc_demos_commit=${RC_DEMOS_SHA}"
  echo "extensions_repo=${EXTENSIONS_REPO}"
  echo "extensions_ref_requested=${EXTENSIONS_REF}"
  echo "extensions_commit=${EXTENSIONS_SHA}"
  echo "go_rc_profiler_repo=${PROFILER_REPO}"
  echo "go_rc_profiler_ref_requested=${PROFILER_REF}"
  echo "go_rc_profiler_commit=${PROFILER_SHA}"
  echo "projection_policy=${POLICY}"
  echo "go=$("$GO_BIN" version)"
  echo "note=rc-demos pin is temporary PR-head SHA from ksteffe/rc-demos; same as Experiment 006"
} >"$GENERATED/environment.txt"

echo "Composing real rc-demos dev-container Profile ..."
(
  cd "$DEMO_ROOT"
  sh ./scripts/compose-dev-container-profile.sh
)

PROFILE="$DEMO_ROOT/artifacts/dev-container.profile.yaml"
PROVENANCE="$DEMO_ROOT/artifacts/dev-container.provenance.yaml"
[[ -f "$PROFILE" ]] || { echo "compose did not produce $PROFILE" >&2; exit 1; }
[[ -f "$PROVENANCE" ]] || { echo "compose did not produce $PROVENANCE" >&2; exit 1; }

cp "$PROFILE" "$GENERATED/dev-container.profile.yaml"
cp "$PROVENANCE" "$GENERATED/dev-container.provenance.yaml"
cp "$DEMO_ROOT/artifacts/application.profiler.yaml" "$GENERATED/application.profiler.yaml"

cat >"$WORK/tmp/summarize.go" <<'EOF'
package main

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

func main() {
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "read: %v\n", err)
		os.Exit(1)
	}
	var doc map[string]any
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		fmt.Fprintf(os.Stderr, "yaml: %v\n", err)
		os.Exit(1)
	}
	meta, _ := doc["metadata"].(map[string]any)
	name, _ := meta["name"].(string)
	conds, _ := doc["conditions"].([]any)
	fmt.Printf("profile_name=%s\n", name)
	fmt.Printf("condition_count=%d\n", len(conds))
	for i, c := range conds {
		cm, _ := c.(map[string]any)
		iface, _ := cm["interface"].(map[string]any)
		ops, hasOps := iface["operations"].([]any)
		access, hasAccess := iface["access"].([]any)
		events, hasEvents := iface["events"].([]any)
		fmt.Printf(
			"condition[%d].name=%v kind=%v interface.type=%v has_operations=%v operations_len=%d has_access=%v access=%v has_events=%v events=%v provider=%v\n",
			i, cm["name"], cm["kind"], iface["type"], hasOps, len(ops), hasAccess, access, hasEvents, events, iface["provider"],
		)
	}
}
EOF
(
  cd "$ROOT"
  "$GO_BIN" run "$WORK/tmp/summarize.go" "$GENERATED/dev-container.profile.yaml"
) | tee "$GENERATED/condition-summary.txt"

echo "Running rc-pade generate against composed Profile ..."
set +e
"$GO_BIN" run "$ROOT/cmd/rc-pade" generate \
  --profile "$GENERATED/dev-container.profile.yaml" \
  --policy "$POLICY" \
  >"$GENERATED/development-session.yaml" \
  2>"$GENERATED/rc-pade.stderr.txt"
status=$?
set -e

{
  echo "rc_pade_generate_exit=${status}"
  if [[ -s "$GENERATED/rc-pade.stderr.txt" ]]; then
    echo "rc_pade_stderr<<"
    cat "$GENERATED/rc-pade.stderr.txt"
    echo ">>"
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "rc_pade_accepted=true"
  else
    echo "rc_pade_accepted=false"
    rm -f "$GENERATED/development-session.yaml"
  fi
} | tee -a "$GENERATED/environment.txt" | tee "$GENERATED/result.txt"

if [[ "$status" -ne 0 ]]; then
  printf 'Experiment 008: rc-pade rejected the composed Profile (unexpected for this experiment).\nStderr: %s\nProfile: %s\n' \
    "$GENERATED/rc-pade.stderr.txt" "$GENERATED/dev-container.profile.yaml" >&2
  exit "$status"
fi

# Assert expected capability intent from the live Profile access set.
cat >"$WORK/tmp/assert_session.go" <<'EOF'
package main

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

func main() {
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fatal(err)
	}
	var doc struct {
		APIVersion string `yaml:"apiVersion"`
		Kind       string `yaml:"kind"`
		Metadata   struct {
			Name        string            `yaml:"name"`
			Annotations map[string]string `yaml:"annotations"`
		} `yaml:"metadata"`
		Spec struct {
			Capabilities map[string]struct {
				Access   string `yaml:"access"`
				Required bool   `yaml:"required"`
			} `yaml:"capabilities"`
		} `yaml:"spec"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		fatal(err)
	}
	if doc.APIVersion != "pade.local/v1alpha1" || doc.Kind != "DevelopmentSession" {
		fatal(fmt.Errorf("unexpected document %s %s", doc.APIVersion, doc.Kind))
	}
	if doc.Metadata.Name != "web-demo-dev-container" {
		fatal(fmt.Errorf("name = %q", doc.Metadata.Name))
	}
	if len(doc.Spec.Capabilities) != 2 {
		fatal(fmt.Errorf("expected 2 capabilities, got %#v", doc.Spec.Capabilities))
	}
	read, ok := doc.Spec.Capabilities["github.repo.read"]
	if !ok || read.Access != "read" || !read.Required {
		fatal(fmt.Errorf("github.repo.read = %#v", read))
	}
	write, ok := doc.Spec.Capabilities["github.repo.write"]
	if !ok || write.Access != "write" || !write.Required {
		fatal(fmt.Errorf("github.repo.write = %#v", write))
	}
	fmt.Println("session_assertion=ok")
}

func fatal(err error) {
	fmt.Fprintf(os.Stderr, "assert session: %v\n", err)
	os.Exit(1)
}
EOF
(
  cd "$ROOT"
  "$GO_BIN" run "$WORK/tmp/assert_session.go" "$GENERATED/development-session.yaml"
) | tee "$GENERATED/session-assertion.txt"

printf 'Experiment 008: SUCCESS\nSession: %s\n' "$GENERATED/development-session.yaml"
exit 0
