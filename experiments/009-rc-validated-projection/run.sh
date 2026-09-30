#!/usr/bin/env bash
# Experiment 009 — compose the real rc-demos Profile (same pins as 008), gate it
# with the upstream Runtime Conditions resolver/validator, and only then hand the
# identical Profile bytes to the unchanged rc-pade. Cases A–D only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/009-rc-validated-projection"
GENERATED="$EXPERIMENT/generated"
WORK="${RC_PADE_EXPERIMENT_WORK:-$ROOT/.work/experiment-009}"
SIBLINGS="$WORK/siblings"
BIN="$WORK/bin"
TOOLS="$WORK/tools"

# Overrideable pins. Defaults match Experiments 006 and 008 exactly.
RC_DEMOS_REPO="${RC_DEMOS_REPO:-https://github.com/ksteffe/rc-demos.git}"
RC_DEMOS_REF="${RC_DEMOS_REF:-13a85bd4221797c94e209fad576a9d4ab89522f3}"
EXTENSIONS_REPO="${EXTENSIONS_REPO:-https://github.com/runtimeconditions/extensions.git}"
EXTENSIONS_REF="${EXTENSIONS_REF:-7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7}"
PROFILER_REPO="${PROFILER_REPO:-https://github.com/runtimeconditions/go-rc-profiler.git}"
PROFILER_REF="${PROFILER_REF:-5d2e860e48842b89ec83414123a7e59228f61d36}"
# Baseline policy is Experiment 008's, unchanged and used by reference.
BASELINE_POLICY="$ROOT/experiments/008-rc-field-projection/policy.yaml"
NO_CLONE_POLICY="$EXPERIMENT/policy-no-clone.yaml"
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

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cleanup() {
  if [[ "$KEEP_WORK" != "1" ]]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

rm -rf "$WORK" "$GENERATED"
mkdir -p "$SIBLINGS" "$BIN" "$TOOLS/mutate" "$TOOLS/assert" "$GENERATED/profiles" "$GENERATED/cases"

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
# Evidence that production rc-pade is unchanged relative to the recorded commit.
PRODUCTION_DIRTY="$(git -C "$ROOT" status --porcelain -- cmd internal go.mod go.sum)"

echo "Building rc-pade (unchanged production code) ..."
(cd "$ROOT" && "$GO_BIN" build -o "$BIN/rc-pade" ./cmd/rc-pade)

echo "Building rcvalidate (upstream rc-extension-resolver wrapper) ..."
(
  cd "$EXPERIMENT/rcvalidate"
  GOTOOLCHAIN=auto "$GO_BIN" build -o "$BIN/rcvalidate" .
)
RCVALIDATE_GO="$(cd "$EXPERIMENT/rcvalidate" && GOTOOLCHAIN=auto "$GO_BIN" version)"
RESOLVER_VERSION="$(cd "$EXPERIMENT/rcvalidate" && GOTOOLCHAIN=auto "$GO_BIN" list -m -f '{{.Version}}' github.com/runtimeconditions/rc-extension-resolver)"

{
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "rc_pade_commit=${RC_PADE_SHA}"
  echo "rc_pade_branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  if [[ -z "$PRODUCTION_DIRTY" ]]; then
    echo "rc_pade_production_tree=clean (cmd internal go.mod go.sum match rc_pade_commit)"
  else
    echo "rc_pade_production_tree=DIRTY"
    printf '%s\n' "$PRODUCTION_DIRTY" | sed 's/^/rc_pade_production_change=/'
  fi
  echo "rc_demos_repo=${RC_DEMOS_REPO}"
  echo "rc_demos_ref_requested=${RC_DEMOS_REF}"
  echo "rc_demos_commit=${RC_DEMOS_SHA}"
  echo "extensions_repo=${EXTENSIONS_REPO}"
  echo "extensions_ref_requested=${EXTENSIONS_REF}"
  echo "extensions_commit=${EXTENSIONS_SHA}"
  echo "go_rc_profiler_repo=${PROFILER_REPO}"
  echo "go_rc_profiler_ref_requested=${PROFILER_REF}"
  echo "go_rc_profiler_commit=${PROFILER_SHA}"
  echo "validator_module=github.com/runtimeconditions/rc-extension-resolver"
  echo "validator_version=${RESOLVER_VERSION}"
  echo "validator_commit=91c46bf6bcc8207475ade30a6f6c1d9ab810ac2e"
  echo "validator_note=current upstream implementation used by this experiment; not a full sixth-draft conformance validator"
  echo "baseline_policy=experiments/008-rc-field-projection/policy.yaml"
  echo "case_c_policy=experiments/009-rc-validated-projection/policy-no-clone.yaml"
  echo "go_rc_pade=$("$GO_BIN" version)"
  echo "go_rcvalidate=${RCVALIDATE_GO}"
  echo "note=rc-demos pin is temporary PR-head SHA from ksteffe/rc-demos; same as Experiments 006 and 008"
} >"$GENERATED/environment.txt"

DEMO_ROOT="$SIBLINGS/rc-demos/dev-container-profile"
[[ -f "$DEMO_ROOT/scripts/compose-dev-container-profile.sh" ]] || {
  echo "missing compose script under $DEMO_ROOT" >&2
  exit 1
}

echo "Composing real rc-demos dev-container Profile ..."
(
  cd "$DEMO_ROOT"
  sh ./scripts/compose-dev-container-profile.sh
)

COMPOSED="$GENERATED/profiles/composed.profile.yaml"
cp "$DEMO_ROOT/artifacts/dev-container.profile.yaml" "$COMPOSED"
cp "$DEMO_ROOT/artifacts/dev-container.provenance.yaml" "$GENERATED/profiles/composed.provenance.yaml"

# Derived variants for B and C: only interface.access of the source_control
# Condition changes. The tool re-reads its output and checks nothing else moved.
cat >"$TOOLS/mutate/main.go" <<'EOF'
package main

import (
	"bytes"
	"fmt"
	"os"
	"reflect"
	"strings"

	"gopkg.in/yaml.v3"
)

func main() {
	in, out, name, values := os.Args[1], os.Args[2], os.Args[3], strings.Split(os.Args[4], ",")
	raw, err := os.ReadFile(in)
	check(err)

	var doc yaml.Node
	check(yaml.Unmarshal(raw, &doc))
	access := findAccess(doc.Content[0], name)
	if access == nil {
		check(fmt.Errorf("condition %q has no interface.access", name))
	}
	access.Content = nil
	for _, v := range values {
		access.Content = append(access.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: v})
	}

	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(4)
	check(enc.Encode(&doc))
	check(enc.Close())
	check(os.WriteFile(out, buf.Bytes(), 0o644))

	var before, after map[string]any
	check(yaml.Unmarshal(raw, &before))
	check(yaml.Unmarshal(buf.Bytes(), &after))
	expected := make([]any, len(values))
	for i, v := range values {
		expected[i] = v
	}
	for _, c := range before["conditions"].([]any) {
		cm := c.(map[string]any)
		if cm["name"] == name {
			cm["interface"].(map[string]any)["access"] = expected
		}
	}
	if !reflect.DeepEqual(before, after) {
		check(fmt.Errorf("mutation changed more than %s interface.access", name))
	}
	fmt.Printf("variant=%s condition=%s access=%v\n", out, name, values)
}

func findAccess(root *yaml.Node, name string) *yaml.Node {
	conditions := value(root, "conditions")
	if conditions == nil {
		return nil
	}
	for _, c := range conditions.Content {
		if n := value(c, "name"); n != nil && n.Value == name {
			if iface := value(c, "interface"); iface != nil {
				return value(iface, "access")
			}
		}
	}
	return nil
}

func value(m *yaml.Node, key string) *yaml.Node {
	if m == nil || m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "mutate:", err)
		os.Exit(1)
	}
}
EOF

PROFILE_B="$GENERATED/profiles/case-b.profile.yaml"
PROFILE_C="$GENERATED/profiles/case-c.profile.yaml"
(
  cd "$ROOT"
  "$GO_BIN" run "$TOOLS/mutate/main.go" "$COMPOSED" "$PROFILE_B" application-source fetch,admin
  "$GO_BIN" run "$TOOLS/mutate/main.go" "$COMPOSED" "$PROFILE_C" application-source clone
) | tee "$GENERATED/profiles/variants.txt"

# Gated path: rcvalidate must accept the Profile before rc-pade sees it, and
# the bytes rc-pade reads must hash to what the validator accepted.
run_gated_case() {
  local id="$1" profile="$2" policy="$3"
  local dir="$GENERATED/cases/$id"
  mkdir -p "$dir"
  echo "profile=${profile#"$ROOT"/}" >"$dir/inputs.txt"
  echo "policy=${policy#"$ROOT"/}" >>"$dir/inputs.txt"

  sha256_of "$profile" >"$dir/profile.sha256.before-validation"

  set +e
  "$BIN/rcvalidate" \
    -profile "$profile" \
    -extensions-root "$SIBLINGS/extensions" \
    -report "$dir/validation-report.yaml" \
    >"$dir/validation.stdout" 2>"$dir/validation.stderr"
  echo "$?" >"$dir/validation.exit"
  set -e

  sha256_of "$profile" >"$dir/profile.sha256.after-validation"

  if [[ "$(cat "$dir/validation.exit")" != "0" ]]; then
    echo "rc-pade not invoked: validation gate rejected the Profile" >"$dir/projection.skipped"
    return 0
  fi

  local accepted_sha
  accepted_sha="$(sed -n 's/^accepted=true sha256=\([0-9a-f]\{64\}\)$/\1/p' "$dir/validation.stdout")"
  sha256_of "$profile" >"$dir/profile.sha256.passed-to-rc-pade"
  if [[ -z "$accepted_sha" || "$accepted_sha" != "$(cat "$dir/profile.sha256.passed-to-rc-pade")" ]]; then
    echo "rc-pade not invoked: Profile bytes differ from the bytes the validation gate accepted" >"$dir/projection.skipped"
    return 0
  fi
  set +e
  "$BIN/rc-pade" generate --profile "$profile" --policy "$policy" \
    >"$dir/projection.stdout" 2>"$dir/projection.stderr"
  echo "$?" >"$dir/projection.exit"
  set -e
  sha256_of "$profile" >"$dir/profile.sha256.after-projection"

  if [[ "$(cat "$dir/projection.exit")" == "0" ]]; then
    cp "$dir/projection.stdout" "$dir/development-session.yaml"
  fi
}

# Evidence only: bypass the gate to confirm rc-pade's own cover check still
# fails closed on the RC-invalid Profile.
run_bypass() {
  local id="$1" profile="$2" policy="$3"
  local dir="$GENERATED/cases/$id/bypass"
  mkdir -p "$dir"
  echo "profile=${profile#"$ROOT"/}" >"$dir/inputs.txt"
  echo "policy=${policy#"$ROOT"/}" >>"$dir/inputs.txt"
  echo "note=gate intentionally bypassed; not part of the normal pipeline" >>"$dir/inputs.txt"
  set +e
  "$BIN/rc-pade" generate --profile "$profile" --policy "$policy" \
    >"$dir/projection.stdout" 2>"$dir/projection.stderr"
  echo "$?" >"$dir/projection.exit"
  set -e
}

echo "Running cases ..."
# A and D share the unmodified composed Profile and the 008 policy.
run_gated_case A "$COMPOSED" "$BASELINE_POLICY"
run_gated_case B "$PROFILE_B" "$BASELINE_POLICY"
run_bypass B "$PROFILE_B" "$BASELINE_POLICY"
run_gated_case C "$PROFILE_C" "$NO_CLONE_POLICY"

cat >"$TOOLS/assert/main.go" <<'EOF'
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

var failures int

func main() {
	generated, baselinePolicy := os.Args[1], os.Args[2]
	cases := filepath.Join(generated, "cases")
	composed := filepath.Join(generated, "profiles", "composed.profile.yaml")

	caseA(filepath.Join(cases, "A"), composed)
	caseB(filepath.Join(cases, "B"))
	caseC(filepath.Join(cases, "C"))
	caseD(filepath.Join(cases, "A"), composed, baselinePolicy)
	profileInvariants(generated)

	if failures > 0 {
		fmt.Printf("RESULT FAIL (%d failed assertions)\n", failures)
		os.Exit(1)
	}
	fmt.Println("RESULT PASS")
}

func caseA(dir, composed string) {
	c := "A"
	expectValidation(c, dir, true, nil)
	expectGateIntegrity(c, dir)
	expectEqual(c, "projection exit", read(dir, "projection.exit"), "0")
	session := readSession(c, dir)
	if session == nil {
		return
	}
	want := map[string]capability{
		"github.repo.read":  {Access: "read", Required: true},
		"github.repo.write": {Access: "write", Required: true},
	}
	expectCapabilities(c, session, want)
	expectNoTargetBinding(c, dir)
}

func caseB(dir string) {
	c := "B"
	expectValidation(c, dir, false, map[int]bool{2: true})
	expectEqual(c, "profile unchanged by validation", read(dir, "profile.sha256.before-validation"), read(dir, "profile.sha256.after-validation"))
	expect(c, "rc-pade not invoked on gated path", exists(dir, "projection.skipped") && !exists(dir, "projection.exit") && !exists(dir, "development-session.yaml"))
	bypass := filepath.Join(dir, "bypass")
	expect(c, "bypass: rc-pade exits non-zero", read(bypass, "projection.exit") != "0")
	expect(c, "bypass: rc-pade names the uncovered value admin", strings.Contains(read(bypass, "projection.stderr"), `"admin"`))
	expectEqual(c, "bypass: no session on stdout", read(bypass, "projection.stdout"), "")
}

func caseC(dir string) {
	c := "C"
	expectValidation(c, dir, true, nil)
	expectGateIntegrity(c, dir)
	expect(c, "rc-pade projection fails", read(dir, "projection.exit") != "0")
	expect(c, "no DevelopmentSession produced", !exists(dir, "development-session.yaml") && read(dir, "projection.stdout") == "")
	stderr := read(dir, "projection.stderr")
	expect(c, "failure identifies uncovered access value clone", strings.Contains(stderr, `"clone"`) && strings.Contains(stderr, "interface.access"))
}

func caseD(dirA, composed, policyPath string) {
	c := "D"
	var report validationReport
	loadYAML(c, filepath.Join(dirA, "validation-report.yaml"), &report)
	for _, scope := range []string{"api/http", "google.analytics/web"} {
		found := false
		for _, cond := range report.Conditions {
			if cond.Kind+"/"+cond.InterfaceType == scope {
				found = true
				expect(c, scope+" accepted by validation", cond.Valid)
			}
		}
		expect(c, scope+" present in validated Profile", found)
	}

	var policy struct {
		Rules []map[string]any `yaml:"rules"`
	}
	loadYAML(c, policyPath, &policy)
	for _, scope := range [][2]string{{"api", "http"}, {"google.analytics", "web"}} {
		matches := 0
		for _, rule := range policy.Rules {
			m, _ := rule["match"].(map[string]any)
			if m["kind"] != scope[0] || m["interfaceType"] != scope[1] {
				continue
			}
			matches++
			outside, _ := rule["outsidePADE"].(bool)
			_, hasProject := rule["project"]
			_, hasOps := rule["operations"]
			expect(c, scope[0]+"/"+scope[1]+" explicitly outsidePADE in 008 policy", outside && !hasProject && !hasOps)
		}
		expectEqual(c, scope[0]+"/"+scope[1]+" matching rule count", fmt.Sprint(matches), "1")
	}

	session := readSession(c, dirA)
	if session == nil {
		return
	}
	for name := range session.Spec.Capabilities {
		expect(c, "capability "+name+" is not from api/http or google.analytics/web", strings.HasPrefix(name, "github.repo."))
	}
}

// Workload identity (workload.uri) is provenance and is allowed. What must
// not appear is a concrete target-resource binding for any Condition, or
// credentials / account / bucket / token / fulfillment configuration.
var forbiddenKeys = []string{
	"repository", "repositoryurl", "repo", "url", "target", "targets", "binding", "bindings",
	"credential", "credentials", "token", "secret", "password", "account", "accountid",
	"bucket", "bucketname", "endpoint", "material", "materials", "fulfillment", "provisioning",
}

func profileInvariants(generated string) {
	c := "invariants"
	for _, name := range []string{"composed.profile.yaml", "case-b.profile.yaml", "case-c.profile.yaml"} {
		var doc map[string]any
		loadYAML(c, filepath.Join(generated, "profiles", name), &doc)
		conds, _ := doc["conditions"].([]any)
		for _, cond := range conds {
			cm, _ := cond.(map[string]any)
			label := fmt.Sprintf("%s %v", name, cm["name"])
			hits := walkForbidden(cm, "")
			expect(c, label+": no target binding / credential keys in Condition", len(hits) == 0)
			for _, h := range hits {
				fmt.Printf("  forbidden key: %s\n", h)
			}
			if cm["kind"] == "source_control" {
				iface, _ := cm["interface"].(map[string]any)
				keys := sortedKeys(iface)
				expectEqual(c, label+": source_control interface keys", strings.Join(keys, ","), "access,provider,type")
			}
		}
	}
}

func walkForbidden(v any, path string) []string {
	var hits []string
	switch t := v.(type) {
	case map[string]any:
		for k, child := range t {
			p := path + "." + k
			for _, f := range forbiddenKeys {
				if strings.ToLower(k) == f {
					hits = append(hits, p)
				}
			}
			hits = append(hits, walkForbidden(child, p)...)
		}
	case []any:
		for i, child := range t {
			hits = append(hits, walkForbidden(child, fmt.Sprintf("%s[%d]", path, i))...)
		}
	}
	return hits
}

type validationReport struct {
	Profile struct {
		SHA256 string `yaml:"sha256"`
	} `yaml:"profile"`
	Accepted   bool `yaml:"accepted"`
	Conditions []struct {
		Index         int      `yaml:"index"`
		Kind          string   `yaml:"kind"`
		InterfaceType string   `yaml:"interfaceType"`
		Valid         bool     `yaml:"valid"`
		Errors        []string `yaml:"errors"`
	} `yaml:"conditions"`
}

func expectValidation(c, dir string, accepted bool, invalid map[int]bool) {
	wantExit := "0"
	if !accepted {
		wantExit = "1"
	}
	expectEqual(c, "validation exit", read(dir, "validation.exit"), wantExit)
	var report validationReport
	loadYAML(c, filepath.Join(dir, "validation-report.yaml"), &report)
	expect(c, fmt.Sprintf("validation report accepted=%t", accepted), report.Accepted == accepted)
	expectEqual(c, "validated condition count", fmt.Sprint(len(report.Conditions)), "3")
	for _, cond := range report.Conditions {
		wantValid := !invalid[cond.Index]
		expect(c, fmt.Sprintf("conditions[%d] %s/%s valid=%t", cond.Index, cond.Kind, cond.InterfaceType, wantValid), cond.Valid == wantValid)
	}
	expectEqual(c, "validator hashed the file it was given", report.Profile.SHA256, read(dir, "profile.sha256.before-validation"))
}

func expectGateIntegrity(c, dir string) {
	var report validationReport
	loadYAML(c, filepath.Join(dir, "validation-report.yaml"), &report)
	accepted := report.Profile.SHA256
	expectEqual(c, "sha256 after validation == accepted", read(dir, "profile.sha256.after-validation"), accepted)
	expectEqual(c, "sha256 passed to rc-pade == accepted", read(dir, "profile.sha256.passed-to-rc-pade"), accepted)
	expectEqual(c, "sha256 after projection == accepted", read(dir, "profile.sha256.after-projection"), accepted)
}

type capability struct {
	Access   string `yaml:"access"`
	Required bool   `yaml:"required"`
}

type session struct {
	APIVersion string `yaml:"apiVersion"`
	Kind       string `yaml:"kind"`
	Metadata   struct {
		Name        string            `yaml:"name"`
		Annotations map[string]string `yaml:"annotations"`
	} `yaml:"metadata"`
	Spec struct {
		Capabilities map[string]capability `yaml:"capabilities"`
	} `yaml:"spec"`
}

func readSession(c, dir string) *session {
	path := filepath.Join(dir, "development-session.yaml")
	raw, err := os.ReadFile(path)
	if err != nil {
		expect(c, "development-session.yaml exists", false)
		return nil
	}
	var s session
	dec := yaml.NewDecoder(strings.NewReader(string(raw)))
	dec.KnownFields(true)
	if err := dec.Decode(&s); err != nil {
		expect(c, "session has only apiVersion/kind/metadata(name,annotations)/spec.capabilities(access,required): "+err.Error(), false)
		return nil
	}
	expect(c, "session is pade.local/v1alpha1 DevelopmentSession", s.APIVersion == "pade.local/v1alpha1" && s.Kind == "DevelopmentSession")
	expectEqual(c, "session name", s.Metadata.Name, "web-demo-dev-container")
	return &s
}

func expectCapabilities(c string, s *session, want map[string]capability) {
	expectEqual(c, "capability names", strings.Join(sortedKeys(s.Spec.Capabilities), ","), strings.Join(sortedKeys(want), ","))
	for name, w := range want {
		got, ok := s.Spec.Capabilities[name]
		expect(c, fmt.Sprintf("%s access=%s required=%t", name, w.Access, w.Required), ok && got == w)
	}
}

func expectNoTargetBinding(c, dir string) {
	var doc map[string]any
	loadYAML(c, filepath.Join(dir, "development-session.yaml"), &doc)
	spec, _ := doc["spec"].(map[string]any)
	hits := walkForbidden(spec, "spec")
	expect(c, "no repository target / credential / fulfillment binding in session spec", len(hits) == 0)
	meta, _ := doc["metadata"].(map[string]any)
	ann, _ := meta["annotations"].(map[string]any)
	allowed := map[string]bool{
		"rc-pade.local/source-profile":          true,
		"rc-pade.local/source-workload-uri":     true,
		"rc-pade.local/source-workload-version": true,
	}
	for k := range ann {
		expect(c, "annotation "+k+" is workload provenance only", allowed[k])
	}
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func loadYAML(c, path string, into any) {
	raw, err := os.ReadFile(path)
	if err == nil {
		err = yaml.Unmarshal(raw, into)
	}
	if err != nil {
		expect(c, "load "+filepath.Base(path)+": "+err.Error(), false)
	}
}

func read(dir, name string) string {
	raw, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return "<missing " + name + ">"
	}
	return strings.TrimSpace(string(raw))
}

func exists(dir, name string) bool {
	_, err := os.Stat(filepath.Join(dir, name))
	return err == nil
}

func expectEqual(c, what, got, want string) {
	if got == want {
		fmt.Printf("PASS [%s] %s\n", c, what)
		return
	}
	failures++
	fmt.Printf("FAIL [%s] %s: got %q want %q\n", c, what, got, want)
}

func expect(c, what string, ok bool) {
	if ok {
		fmt.Printf("PASS [%s] %s\n", c, what)
		return
	}
	failures++
	fmt.Printf("FAIL [%s] %s\n", c, what)
}
EOF

echo "Asserting outcomes ..."
set +e
(
  cd "$ROOT"
  "$GO_BIN" run "$TOOLS/assert/main.go" "$GENERATED" "$BASELINE_POLICY"
) >"$GENERATED/assertions.txt" 2>&1
assert_status=$?
set -e
cat "$GENERATED/assertions.txt"

case_line() {
  local id="$1" dir="$GENERATED/cases/$1"
  local projection="not invoked (gate rejected)"
  if [[ -f "$dir/projection.exit" ]]; then
    projection="exit=$(cat "$dir/projection.exit")"
  fi
  printf 'case=%s validation_exit=%s projection=%s\n' "$id" "$(cat "$dir/validation.exit")" "$projection"
}

{
  echo "experiment=009-rc-validated-projection"
  echo "validator=github.com/runtimeconditions/rc-extension-resolver@${RESOLVER_VERSION}"
  case_line A
  case_line B
  echo "case=B-bypass projection=exit=$(cat "$GENERATED/cases/B/bypass/projection.exit") (evidence only)"
  case_line C
  echo "case=D covered by case A Profile/session"
  echo "failed_assertions=$(grep -c '^FAIL' "$GENERATED/assertions.txt" || true)"
  echo "passed_assertions=$(grep -c '^PASS' "$GENERATED/assertions.txt" || true)"
  if [[ "$assert_status" -eq 0 ]]; then
    echo "result=PASS"
  else
    echo "result=FAIL"
  fi
} | tee "$GENERATED/results.txt"

if [[ "$assert_status" -ne 0 ]]; then
  echo "Experiment 009: assertions failed; see $GENERATED/assertions.txt" >&2
  exit 1
fi
printf 'Experiment 009: SUCCESS\nEvidence: %s\n' "$GENERATED"
