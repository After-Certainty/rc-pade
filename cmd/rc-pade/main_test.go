package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/After-Certainty/rc-pade/internal/model"
	"github.com/After-Certainty/rc-pade/internal/projector"
)

func TestPolicyTyposCannotDisableAuthorityCoverage(t *testing.T) {
	data, err := os.ReadFile("../../experiments/008-rc-field-projection/policy.yaml")
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"cover", "require", "when"} {
		t.Run(field, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "policy.yaml")
			mutated := strings.ReplaceAll(string(data), field+":", field+"Typo:")
			if err := os.WriteFile(path, []byte(mutated), 0600); err != nil {
				t.Fatal(err)
			}
			var policy model.ProjectionPolicy
			if err := readYAML(path, &policy); err == nil {
				t.Fatal("unknown policy field accepted; an operator guard may be lost")
			}
		})
	}
}

func TestPolicyAndProfileRemainSeparateBoundaries(t *testing.T) {
	var policy model.ProjectionPolicy
	if err := readYAML("../../experiments/008-rc-field-projection/policy.yaml", &policy); err != nil {
		t.Fatal(err)
	}
	for _, access := range []string{"fetch", "fetch, admin"} {
		path := filepath.Join(t.TempDir(), "profile.yaml")
		data := `apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata: {name: security-fixture}
extensions: [https://example.invalid/extension.yaml]
conditions:
  - kind: source_control
    interface:
      type: git
      provider: github
      access: [` + access + `]
      extensionOwnedField: preserved
`
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
		var profile model.RuntimeConditionsProfile
		if err := readYAML(path, &profile); err != nil {
			t.Fatal(err)
		}
		if profile.Conditions[0].Interface.Fields["extensionOwnedField"] != "preserved" {
			t.Fatal("opaque extension data lost")
		}
		session, err := projector.Project(profile, policy, "")
		if access == "fetch" {
			if err != nil || len(session.Spec.Capabilities) != 1 {
				t.Fatal("supported demand did not project")
			}
		} else if err == nil || len(session.Spec.Capabilities) != 0 {
			t.Fatal("unsupported authority must produce no session")
		}
	}
}

func TestPolicyRejectsTrailingDocument(t *testing.T) {
	data, err := os.ReadFile("../../examples/s3-put-object/policy.yaml")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "policy.yaml")
	if err := os.WriteFile(path, append(data, []byte("\n---\nrules: []\n")...), 0600); err != nil {
		t.Fatal(err)
	}
	var policy model.ProjectionPolicy
	if err := readYAML(path, &policy); err == nil {
		t.Fatal("trailing document accepted")
	}
}
