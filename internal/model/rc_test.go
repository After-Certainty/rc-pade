package model

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestRCInterfacePreservesExtensionFields(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: preserve-test
conditions:
  - kind: source_control
    interface:
      type: git
      provider: github
      access:
        - fetch
        - pull
        - push
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	iface := profile.Conditions[0].Interface
	if iface.Type != "git" {
		t.Fatalf("Type = %q, want git", iface.Type)
	}
	if got, _ := iface.Fields["provider"].(string); got != "github" {
		t.Fatalf("provider = %#v, want github", iface.Fields["provider"])
	}
	access, ok := iface.Fields["access"].([]any)
	if !ok || len(access) != 3 {
		t.Fatalf("access = %#v, want [fetch pull push]", iface.Fields["access"])
	}
	if access[0] != "fetch" || access[1] != "pull" || access[2] != "push" {
		t.Fatalf("access values = %#v", access)
	}
	if len(iface.Operations) != 0 {
		t.Fatalf("Operations = %#v, want empty", iface.Operations)
	}
}

func TestRCInterfaceStillLoadsS3Operations(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: s3-test
conditions:
  - kind: aws.s3
    interface:
      type: bucket
      operations:
        - name: PutObject
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	iface := profile.Conditions[0].Interface
	if iface.Type != "bucket" {
		t.Fatalf("Type = %q", iface.Type)
	}
	if len(iface.Operations) != 1 || iface.Operations[0].Name != "PutObject" {
		t.Fatalf("Operations = %#v", iface.Operations)
	}
	if iface.Fields["type"] != "bucket" {
		t.Fatalf("Fields.type = %#v", iface.Fields["type"])
	}
	if iface.Operations[0].Fields["name"] != "PutObject" {
		t.Fatalf("Operation.Fields = %#v", iface.Operations[0].Fields)
	}
}

func TestOperationMarshalUnmarshalFieldsAuthoritative(t *testing.T) {
	const structured = `
method: GET
path: /todos/{id}
responseSchema:
  id: integer
`
	var op Operation
	if err := yaml.Unmarshal([]byte(structured), &op); err != nil {
		t.Fatalf("unmarshal structured: %v", err)
	}
	if op.Name != "" {
		t.Fatalf("Name = %q, want empty", op.Name)
	}
	if op.Fields["method"] != "GET" || op.Fields["path"] != "/todos/{id}" {
		t.Fatalf("Fields = %#v", op.Fields)
	}
	out, err := yaml.Marshal(op)
	if err != nil {
		t.Fatalf("marshal structured: %v", err)
	}
	var round Operation
	if err := yaml.Unmarshal(out, &round); err != nil {
		t.Fatalf("remarshal unmarshal: %v", err)
	}
	if round.Name != "" || round.Fields["method"] != "GET" || round.Fields["path"] != "/todos/{id}" {
		t.Fatalf("structured round-trip = %#v", round)
	}

	// Legacy Name-only: Fields nil, MarshalYAML emits {"name": ...}.
	legacy := Operation{Name: "PutObject"}
	legacyOut, err := yaml.Marshal(legacy)
	if err != nil {
		t.Fatalf("marshal legacy: %v", err)
	}
	var legacyRound Operation
	if err := yaml.Unmarshal(legacyOut, &legacyRound); err != nil {
		t.Fatalf("unmarshal legacy: %v", err)
	}
	if legacyRound.Name != "PutObject" {
		t.Fatalf("legacy Name = %q", legacyRound.Name)
	}
	if legacyRound.Fields["name"] != "PutObject" {
		t.Fatalf("legacy Fields after decode = %#v", legacyRound.Fields)
	}

	// Fields set is authoritative on marshal even if Name differs.
	mutated := Operation{
		Name:   "stale",
		Fields: map[string]any{"name": "PutObject", "extra": true},
	}
	mutatedOut, err := yaml.Marshal(mutated)
	if err != nil {
		t.Fatalf("marshal mutated: %v", err)
	}
	var mutatedMap map[string]any
	if err := yaml.Unmarshal(mutatedOut, &mutatedMap); err != nil {
		t.Fatalf("unmarshal mutated map: %v", err)
	}
	if mutatedMap["name"] != "PutObject" || mutatedMap["extra"] != true {
		t.Fatalf("Fields should be authoritative on marshal, got %#v", mutatedMap)
	}
}

func TestConditionLabelNamedAndUnnamed(t *testing.T) {
	if got := ConditionLabel(Condition{Name: "repo"}, 3); got != "repo" {
		t.Fatalf("named label = %q", got)
	}
	if got := ConditionLabel(Condition{}, 1); got != "condition[1]" {
		t.Fatalf("unnamed label = %q", got)
	}
}

func TestNamedAndUnnamedConditionsDecode(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: mixed-names
conditions:
  - name: named-git
    kind: source_control
    interface:
      type: git
      provider: github
  - kind: api
    interface:
      type: http
  - kind: cache
    interface:
      type: key_value
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(profile.Conditions) != 3 {
		t.Fatalf("conditions = %d", len(profile.Conditions))
	}
	if profile.Conditions[0].Name != "named-git" {
		t.Fatalf("name[0] = %q", profile.Conditions[0].Name)
	}
	if profile.Conditions[1].Name != "" || profile.Conditions[2].Name != "" {
		t.Fatalf("expected unnamed conditions, got %#v %#v", profile.Conditions[1].Name, profile.Conditions[2].Name)
	}
	if ConditionLabel(profile.Conditions[1], 1) != "condition[1]" {
		t.Fatalf("label[1] = %q", ConditionLabel(profile.Conditions[1], 1))
	}
}

func TestMultipleUnnamedConditionsDecode(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: unnamed-pair
conditions:
  - kind: api
    interface:
      type: http
  - kind: cache
    interface:
      type: key_value
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if profile.Conditions[0].Name != "" || profile.Conditions[1].Name != "" {
		t.Fatalf("names unexpectedly set: %#v", profile.Conditions)
	}
}

func TestCurrentExtensionReferencesDecode(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: extensions-test
extensions:
  - https://runtimeconditions.io/extensions/rc/common-integrations:v1alpha2
  - https://runtimeconditions.io/extensions/rc/env-configuration:v1alpha2
conditions:
  - kind: api
    interface:
      type: http
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(profile.Extensions) != 2 {
		t.Fatalf("extensions = %#v", profile.Extensions)
	}
	if profile.Extensions[0] != "https://runtimeconditions.io/extensions/rc/common-integrations:v1alpha2" {
		t.Fatalf("extension[0] = %q", profile.Extensions[0])
	}
}

func TestExtendedInterfaceAndConfigurationPreservation(t *testing.T) {
	const raw = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: http-config
extensions:
  - https://runtimeconditions.io/extensions/rc/common-integrations:v1alpha2
  - https://runtimeconditions.io/extensions/rc/env-configuration:v1alpha2
conditions:
  - kind: api
    configuration:
      env:
        - name: TODOS_API_URL
          property: baseUrl
    interface:
      type: http
      operations:
        - method: GET
          path: /todos/{id}
          responseSchema:
            id: integer
      spec:
        format: openapi
        uri: catalog://api/default/todos-api
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(raw), &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	cond := profile.Conditions[0]
	if cond.Name != "" {
		t.Fatalf("expected unnamed condition, got %q", cond.Name)
	}
	env, ok := cond.Configuration["env"].([]any)
	if !ok || len(env) != 1 {
		t.Fatalf("configuration.env = %#v", cond.Configuration)
	}
	iface := cond.Interface
	if iface.Type != "http" {
		t.Fatalf("type = %q", iface.Type)
	}
	if len(iface.Operations) != 1 {
		t.Fatalf("operations = %#v", iface.Operations)
	}
	op := iface.Operations[0]
	if op.Name != "" {
		t.Fatalf("operation name should be empty, got %q", op.Name)
	}
	if op.Fields["method"] != "GET" {
		t.Fatalf("operation.method = %#v", op.Fields["method"])
	}
	if op.Fields["path"] != "/todos/{id}" {
		t.Fatalf("operation.path = %#v", op.Fields["path"])
	}
	spec, ok := iface.Fields["spec"].(map[string]any)
	if !ok || spec["format"] != "openapi" {
		t.Fatalf("interface.spec = %#v", iface.Fields["spec"])
	}

	// Semantic remashal preserves extension-defined fields. This is not a
	// trusted-handoff path: verified Profile consumption must use exact bytes.
	out, err := yaml.Marshal(profile)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var round RuntimeConditionsProfile
	if err := yaml.Unmarshal(out, &round); err != nil {
		t.Fatalf("remarshal unmarshal: %v", err)
	}
	if round.Conditions[0].Configuration["env"] == nil {
		t.Fatalf("configuration lost on remashal: %#v", round.Conditions[0].Configuration)
	}
	if round.Conditions[0].Interface.Operations[0].Fields["method"] != "GET" {
		t.Fatalf("operation fields lost on remashal: %#v", round.Conditions[0].Interface.Operations[0].Fields)
	}
	if len(round.Extensions) != 2 {
		t.Fatalf("extensions lost on remashal: %#v", round.Extensions)
	}
}

func TestMalformedInterfaceRejected(t *testing.T) {
	const missingType = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: bad
conditions:
  - kind: api
    interface:
      operations:
        - method: GET
`
	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal([]byte(missingType), &profile); err == nil {
		t.Fatal("expected error for missing interface.type")
	}

	const badOpName = `
apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata:
  name: bad-op
conditions:
  - kind: aws.s3
    interface:
      type: bucket
      operations:
        - name: [not, a, string]
`
	if err := yaml.Unmarshal([]byte(badOpName), &profile); err == nil {
		t.Fatal("expected error for non-string operation.name")
	}
}

func TestPublishedRequestLoggerProfileFixture(t *testing.T) {
	const wantSHA = "c2c329da322f9dffca00be55e913e4c019d24e0f6848d4946c89b65d35b7c666"

	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	path := filepath.Join(filepath.Dir(thisFile), "..", "..", "testdata", "published", "request-logger-http.profile.yaml")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	sum := sha256.Sum256(raw)
	gotSHA := hex.EncodeToString(sum[:])
	if gotSHA != wantSHA {
		t.Fatalf("fixture SHA-256 = %s, want %s (exact upstream bytes required)", gotSHA, wantSHA)
	}

	var profile RuntimeConditionsProfile
	if err := yaml.Unmarshal(raw, &profile); err != nil {
		t.Fatalf("unmarshal published profile: %v", err)
	}
	if profile.Metadata.Name != "request-logger-http" {
		t.Fatalf("metadata.name = %q", profile.Metadata.Name)
	}
	if len(profile.Extensions) != 2 {
		t.Fatalf("extensions = %#v", profile.Extensions)
	}
	if profile.Extensions[0] != "https://runtimeconditions.io/extensions/rc/common-integrations:v1alpha2" {
		t.Fatalf("extension[0] = %q", profile.Extensions[0])
	}
	if profile.Extensions[1] != "https://runtimeconditions.io/extensions/rc/env-configuration:v1alpha2" {
		t.Fatalf("extension[1] = %q", profile.Extensions[1])
	}
	if len(profile.Conditions) != 2 {
		t.Fatalf("conditions = %d", len(profile.Conditions))
	}
	if profile.Conditions[0].Name != "" || profile.Conditions[1].Name != "" {
		t.Fatalf("published fixture uses unnamed conditions; got %#v %#v", profile.Conditions[0].Name, profile.Conditions[1].Name)
	}
	if profile.Conditions[0].Kind != "api" || profile.Conditions[0].Interface.Type != "http" {
		t.Fatalf("condition[0] = %s/%s", profile.Conditions[0].Kind, profile.Conditions[0].Interface.Type)
	}
	if profile.Conditions[1].Kind != "cache" || profile.Conditions[1].Interface.Type != "key_value" {
		t.Fatalf("condition[1] = %s/%s", profile.Conditions[1].Kind, profile.Conditions[1].Interface.Type)
	}
	if profile.Conditions[0].Configuration["env"] == nil {
		t.Fatalf("api configuration lost: %#v", profile.Conditions[0].Configuration)
	}
	if profile.Conditions[1].Configuration["alternatives"] == nil {
		t.Fatalf("cache configuration lost: %#v", profile.Conditions[1].Configuration)
	}
	op := profile.Conditions[0].Interface.Operations[0]
	if op.Name != "" || op.Fields["method"] != "GET" {
		t.Fatalf("http operation = name:%q fields:%#v", op.Name, op.Fields)
	}
	if got, _ := profile.Conditions[1].Interface.Fields["engine"].(string); got != "redis" {
		t.Fatalf("cache engine = %#v", profile.Conditions[1].Interface.Fields["engine"])
	}
}
