package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSamePathResolvesSymlinkedParents(t *testing.T) {
	dir := t.TempDir()
	realDir := filepath.Join(dir, "real")
	if err := os.Mkdir(realDir, 0700); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(dir, "alias")
	if err := os.Symlink(realDir, alias); err != nil {
		t.Fatal(err)
	}
	a := filepath.Join(realDir, "bindings.yaml")
	b := filepath.Join(alias, "bindings.yaml")
	same, err := samePath(a, b)
	if err != nil {
		t.Fatal(err)
	}
	if !same {
		t.Fatalf("expected %q and %q to be the same via symlink parent", a, b)
	}
}

func TestSamePathDistinctFiles(t *testing.T) {
	dir := t.TempDir()
	same, err := samePath(filepath.Join(dir, "a.yaml"), filepath.Join(dir, "b.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if same {
		t.Fatal("distinct files must not collide")
	}
}

func TestRejectOutputInputConflictsIgnoresDuplicateInputs(t *testing.T) {
	dir := t.TempDir()
	shared := filepath.Join(dir, "shared.yaml")
	output := filepath.Join(dir, "bindings.yaml")
	if err := os.WriteFile(shared, []byte("x: 1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	err := rejectOutputInputConflicts(bindOptions{
		verifiedProfile: shared,
		policy:          shared,
		broker:          filepath.Join(dir, "broker.json"),
		output:          output,
	})
	if err != nil {
		t.Fatalf("duplicate inputs with distinct --output must pass pre-revoke check, got %v", err)
	}
}

func TestRejectOutputInputConflictsDetectsOutputVsInput(t *testing.T) {
	dir := t.TempDir()
	shared := filepath.Join(dir, "profile.yaml")
	err := rejectOutputInputConflicts(bindOptions{
		verifiedProfile: shared,
		policy:          filepath.Join(dir, "policy.yaml"),
		broker:          filepath.Join(dir, "broker.json"),
		output:          shared,
	})
	if err == nil || !strings.Contains(err.Error(), "--output") {
		t.Fatalf("expected --output vs input collision, got %v", err)
	}
}
