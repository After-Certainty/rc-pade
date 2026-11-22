package main

import (
	"os"
	"path/filepath"
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
