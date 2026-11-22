package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateContinueRequiresSupportReport(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.yaml")
	policy := filepath.Join(dir, "policy.yaml")
	if err := os.WriteFile(profile, []byte(`apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata: {name: gen-continue}
conditions:
  - kind: aws.s3
    interface: {type: bucket, operations: [{name: PutObject}]}
  - optional: true
    kind: api
    interface: {type: http}
`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(policy, []byte(`apiVersion: rc-pade.local/v1alpha1
kind: ProjectionPolicy
onUnsupportedOptional: continue
rules:
  - match: {kind: aws.s3, interfaceType: bucket}
    operations:
      PutObject: {capability: aws.s3.bucket.write, access: write}
`), 0600); err != nil {
		t.Fatal(err)
	}

	_, err := runGenerateOpts(generateOptions{profile: profile, policy: policy})
	if err == nil || !strings.Contains(err.Error(), "--support-report") {
		t.Fatalf("expected --support-report requirement, got %v", err)
	}
}

func TestGenerateContinueWithSupportReportSucceeds(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.yaml")
	policy := filepath.Join(dir, "policy.yaml")
	report := filepath.Join(dir, "support.yaml")
	if err := os.WriteFile(profile, []byte(`apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata: {name: gen-continue-ok}
conditions:
  - kind: aws.s3
    interface: {type: bucket, operations: [{name: PutObject}]}
  - optional: true
    kind: api
    interface: {type: http}
`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(policy, []byte(`apiVersion: rc-pade.local/v1alpha1
kind: ProjectionPolicy
onUnsupportedOptional: continue
rules:
  - match: {kind: aws.s3, interfaceType: bucket}
    operations:
      PutObject: {capability: aws.s3.bucket.write, access: write}
`), 0600); err != nil {
		t.Fatal(err)
	}

	out, err := runGenerateOpts(generateOptions{profile: profile, policy: policy, supportReport: report})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), "aws.s3.bucket.write") {
		t.Fatalf("session missing capability: %s", out)
	}
	raw, err := os.ReadFile(report)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "unsupported_optional") || !strings.Contains(string(raw), "complete: true") {
		t.Fatalf("support report = %s", raw)
	}
}

func TestGenerateRejectsSupportReportProfileCollision(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.yaml")
	policy := filepath.Join(dir, "policy.yaml")
	if err := os.WriteFile(profile, []byte(`apiVersion: runtimeconditions.io/v1alpha1
kind: RuntimeConditionsProfile
metadata: {name: collide}
conditions:
  - kind: aws.s3
    interface: {type: bucket, operations: [{name: PutObject}]}
`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(policy, []byte(`apiVersion: rc-pade.local/v1alpha1
kind: ProjectionPolicy
rules:
  - match: {kind: aws.s3, interfaceType: bucket}
    operations:
      PutObject: {capability: aws.s3.bucket.write, access: write}
`), 0600); err != nil {
		t.Fatal(err)
	}
	_, err := runGenerateOpts(generateOptions{profile: profile, policy: policy, supportReport: profile})
	if err == nil || !strings.Contains(err.Error(), "collides") {
		t.Fatalf("expected collision error, got %v", err)
	}
}
