package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

type bindFixture struct {
	o bindOptions
}

func newBindFixture(t *testing.T) bindFixture {
	t.Helper()
	dir := t.TempDir()

	profile, err := os.ReadFile("../../examples/s3-put-object/runtime-conditions.yaml")
	if err != nil {
		t.Fatal(err)
	}
	policy, err := os.ReadFile("../../examples/s3-put-object/policy.yaml")
	if err != nil {
		t.Fatal(err)
	}

	write := func(name string, contents []byte) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, contents, 0600); err != nil {
			t.Fatal(err)
		}
		return path
	}

	return bindFixture{o: bindOptions{
		verifiedProfile: write("verified-profile.yaml", profile),
		policy:          write("policy.yaml", policy),
		broker: write("broker.json", []byte(
			`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"example-audience","identity":"gce"}}`,
		)),
		allowed: "aws.s3.bucket.write",
		output:  filepath.Join(dir, "bindings.yaml"),
		session: filepath.Join(dir, "session.yaml"),
	}}
}

func assertConsumerBindings(t *testing.T, path string, want ...string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var config consumerBindings
	if err := yaml.Unmarshal(raw, &config); err != nil {
		t.Fatal(err)
	}
	if config.Version != "0.1" {
		t.Fatalf("version = %q, want 0.1", config.Version)
	}
	if len(config.Capabilities) != len(want) {
		t.Fatalf("capabilities = %#v; want %v", config.Capabilities, want)
	}
	for _, capability := range want {
		got, ok := config.Capabilities[capability]
		if !ok {
			t.Fatalf("missing capability %s", capability)
		}
		if got.Provider != "broker" ||
			got.Broker.Endpoint != "https://broker.example.test" ||
			got.Broker.Audience != "example-audience" ||
			got.Broker.Identity != "gce" {
			t.Fatalf("unexpected binding: %#v", got)
		}
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("bindings mode %v, want 0600", info.Mode().Perm())
	}
}

func TestBindConsumesVerifiedProfileWithoutValidatorReport(t *testing.T) {
	f := newBindFixture(t)
	if err := runBind(f.o); err != nil {
		t.Fatal(err)
	}

	assertConsumerBindings(t, f.o.output, "aws.s3.bucket.write")

	raw, err := os.ReadFile(f.o.session)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "aws.s3.bucket.write") {
		t.Fatalf("missing projected capability: %s", raw)
	}
}

func TestBindFailsClosedAfterOutputIsKnown(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(t *testing.T, f *bindFixture)
	}{
		{
			name: "missing verified profile",
			mutate: func(t *testing.T, f *bindFixture) {
				f.o.verifiedProfile = filepath.Join(filepath.Dir(f.o.verifiedProfile), "missing.yaml")
			},
		},
		{
			name: "malformed verified profile",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.verifiedProfile, []byte("not: [valid"), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "unsupported operator projection",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.policy, []byte("apiVersion: rc-pade.local/v1alpha1\nkind: ProjectionPolicy\nrules: []\n"), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "misspelled operator policy guard",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.policy, []byte("apiVersion: rc-pade.local/v1alpha1\nkind: ProjectionPolicy\nrules:\n  - match: {kind: aws.s3, interfaceType: bucket}\n    covert: [interface.operations]\n"), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "projected capability outside allowlist",
			mutate: func(t *testing.T, f *bindFixture) {
				f.o.allowed = "github.repo.read"
			},
		},
		{
			name: "duplicate allowlist entry",
			mutate: func(t *testing.T, f *bindFixture) {
				f.o.allowed = "aws.s3.bucket.write,aws.s3.bucket.write"
			},
		},
		{
			name: "non broker provider",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.broker, []byte(`{"provider":"exec","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"gce"}}`), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "invalid broker identity",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.broker, []byte(`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"unknown"}}`), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "unknown broker field",
			mutate: func(t *testing.T, f *bindFixture) {
				if err := os.WriteFile(f.o.broker, []byte(`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"gce"},"grant":"admin"}`), 0600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "missing broker binding",
			mutate: func(t *testing.T, f *bindFixture) {
				f.o.broker = filepath.Join(filepath.Dir(f.o.broker), "missing.json")
			},
		},
		{
			name: "relative session output",
			mutate: func(t *testing.T, f *bindFixture) {
				f.o.session = "session.yaml"
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := newBindFixture(t)
			if err := runBind(f.o); err != nil {
				t.Fatal(err)
			}
			assertConsumerBindings(t, f.o.output, "aws.s3.bucket.write")

			tc.mutate(t, &f)
			if err := runBind(f.o); err == nil {
				t.Fatal("expected fail closed")
			}
			assertConsumerBindings(t, f.o.output)
		})
	}
}

func TestBindRejectsRelativeBindingsTarget(t *testing.T) {
	f := newBindFixture(t)
	f.o.output = "bindings.yaml"
	if err := runBind(f.o); err == nil {
		t.Fatal("relative output path should be rejected")
	}
}

func TestBindNoPartialBindingsOnSessionOutputFailure(t *testing.T) {
	f := newBindFixture(t)
	if err := runBind(f.o); err != nil {
		t.Fatal(err)
	}

	parent := filepath.Join(filepath.Dir(f.o.output), "not-a-directory")
	if err := os.WriteFile(parent, []byte("file"), 0600); err != nil {
		t.Fatal(err)
	}
	f.o.session = filepath.Join(parent, "session.yaml")

	if err := runBind(f.o); err == nil {
		t.Fatal("expected session write failure")
	}
	assertConsumerBindings(t, f.o.output)
}
