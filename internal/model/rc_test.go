package model

import (
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
}
