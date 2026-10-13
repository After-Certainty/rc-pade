package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

type testFixture struct {
	o options
	validation validationReport
}

func fixture(t *testing.T) testFixture {
	t.Helper()
	dir := t.TempDir()
	profile, err := os.ReadFile("../../examples/s3-put-object/runtime-conditions.yaml")
	if err != nil { t.Fatal(err) }
	policy, err := os.ReadFile("../../examples/s3-put-object/policy.yaml")
	if err != nil { t.Fatal(err) }
	write := func(name string, contents []byte) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, contents, 0600); err != nil { t.Fatal(err) }
		return path
	}
	sum := sha256.Sum256(profile)
	var report validationReport
	report.Accepted = true
	report.Validator.Module = "github.com/runtimeconditions/rc-extension-resolver"
	report.Validator.Version = "v0.0.0-test"
	report.Profile.SHA256 = hex.EncodeToString(sum[:])
	report.Profile.Bytes = len(profile)
	report.Conditions = make([]struct {
		Index         int    `yaml:"index"`
		Kind          string `yaml:"kind"`
		InterfaceType string `yaml:"interfaceType"`
		Valid         bool   `yaml:"valid"`
	}, 1)
	report.Conditions[0].Index = 0
	report.Conditions[0].Kind = "aws.s3"
	report.Conditions[0].InterfaceType = "bucket"
	report.Conditions[0].Valid = true
	reportBytes, err := yaml.Marshal(report)
	if err != nil { t.Fatal(err) }
	return testFixture{
		o: options{
			profile: write("profile.yaml", profile),
			policy: write("policy.yaml", policy),
			report: write("validation-report.yaml", reportBytes),
			broker: write("broker.json", []byte(`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"example-audience","identity":"gce"}}`)),
			allowed: "aws.s3.bucket.write",
			output: filepath.Join(dir, "bindings.yaml"),
			session: filepath.Join(dir, "session.yaml"),
		},
		validation: report,
	}
}

func assertBindings(t *testing.T, path string, want ...string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil { t.Fatal(err) }
	var config bindings
	if err := yaml.Unmarshal(raw, &config); err != nil { t.Fatal(err) }
	if config.Version != "0.1" { t.Fatalf("version = %s",config.Version) }
	if len(config.Capabilities) != len(want) { t.Fatalf("capabilities = %#v; want %v",config.Capabilities,want) }
	for _, capability := range want {
		got, ok := config.Capabilities[capability]
		if !ok { t.Fatalf("missing capability %s",capability) }
		if got.Provider != "broker" || got.Broker.Endpoint != "https://broker.example.test" ||
			got.Broker.Audience != "example-audience" || got.Broker.Identity != "gce" {
			t.Fatalf("unexpected binding: %#v",got)
		}
	}
	info, err := os.Stat(path)
	if err != nil { t.Fatal(err) }
	if info.Mode().Perm() != 0600 { t.Fatalf("bindings mode %v, want 0600",info.Mode().Perm()) }
}

func TestTrustedValidatedProjection(t *testing.T) {
	f := fixture(t)
	if err := run(f.o); err != nil { t.Fatal(err) }
	assertBindings(t,f.o.output,"aws.s3.bucket.write")
	raw, err := os.ReadFile(f.o.session)
	if err != nil { t.Fatal(err) }
	if !strings.Contains(string(raw),"aws.s3.bucket.write") { t.Fatalf("missing projected capability: %s",raw) }
	// The same policy is required to approve every projected capability.
	f.o.allowed = "github.repo.read"
	if err := run(f.o); err == nil || !strings.Contains(err.Error(),"allowlist") {
		t.Fatalf("unexpected result for disallowed capability: %v",err)
	}
	assertBindings(t,f.o.output) // previous bindings were revoked on error
}

func TestRejectsUntrustedOrUnsupportedInput(t *testing.T) {
	cases := []struct{
		name string
		mutate func(t *testing.T, f *testFixture)
	}{
		{"rejected validation",func(t *testing.T,f *testFixture){f.validation.Accepted=false;writeReport(t,f)}},
		{"forged validation hash",func(t *testing.T,f *testFixture){f.validation.Profile.SHA256=strings.Repeat("0",64);writeReport(t,f)}},
		{"invalid condition",func(t *testing.T,f *testFixture){f.validation.Conditions[0].Valid=false;writeReport(t,f)}},
		{"incomplete report",func(t *testing.T,f *testFixture){f.validation.Conditions=nil;writeReport(t,f)}},
		{"missing report",func(t *testing.T,f *testFixture){f.o.report=filepath.Join(filepath.Dir(f.o.report),"missing.yaml")}},
		{"changed Profile after validation",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.profile,[]byte("invalid: profile\n"),0600);err!=nil{t.Fatal(err)}}},
		{"unsupported operator projection",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.policy,[]byte("apiVersion: rc-pade.local/v1alpha1\nkind: ProjectionPolicy\nrules: []\n"),0600);err!=nil{t.Fatal(err)}}},
		{"misspelled operator policy guard",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.policy,[]byte("apiVersion: rc-pade.local/v1alpha1\nkind: ProjectionPolicy\nrules:\n  - match: {kind: aws.s3, interfaceType: bucket}\n    covert: [interface.operations]\n"),0600);err!=nil{t.Fatal(err)}}},
		{"non broker provider",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.broker,[]byte(`{"provider":"exec","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"gce"}}`),0600);err!=nil{t.Fatal(err)}}},
		{"invalid identity",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.broker,[]byte(`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"unknown"}}`),0600);err!=nil{t.Fatal(err)}}},
		{"missing binding config",func(t *testing.T,f *testFixture){f.o.broker=filepath.Join(filepath.Dir(f.o.broker),"missing.json")}},
		{"unknown broker field",func(t *testing.T,f *testFixture){if err:=os.WriteFile(f.o.broker,[]byte(`{"provider":"broker","broker":{"endpoint":"https://broker.example.test","audience":"aud","identity":"gce"},"grant":"admin"}`),0600);err!=nil{t.Fatal(err)}}},
		{"empty allowlist",func(t *testing.T,f *testFixture){f.o.allowed=""}},
	}
	for _, tc := range cases {
		t.Run(tc.name,func(t *testing.T){
			f := fixture(t)
			if err:=run(f.o);err!=nil {t.Fatal(err)}
			assertBindings(t,f.o.output,"aws.s3.bucket.write")
			tc.mutate(t,&f)
			if err:=run(f.o);err==nil {t.Fatal("expected fail closed") }
			assertBindings(t,f.o.output)
		})
	}
}

func writeReport(t *testing.T, f *testFixture) {
	t.Helper()
	data,err:=yaml.Marshal(f.validation)
	if err!=nil {t.Fatal(err)}
	if err=os.WriteFile(f.o.report,data,0600);err!=nil {t.Fatal(err)}
}

func TestRejectsRelativeTarget(t *testing.T) {
	f := fixture(t)
	f.o.output="bindings.yaml"
	if err:=run(f.o);err==nil {t.Fatal("relative output path should be rejected") }
}

func TestNoPartialBindingsOnSessionOutputFailure(t *testing.T) {
	f:=fixture(t)
	if err:=run(f.o);err!=nil {t.Fatal(err)}
	f.o.session=filepath.Join(filepath.Dir(f.o.output),"does-not-exist-as-dir")
	if err:=os.WriteFile(f.o.session,[]byte("not-a-directory"),0600);err!=nil {t.Fatal(err)}
	f.o.session=filepath.Join(f.o.session,"session.yaml")
	if err:=run(f.o);err==nil {t.Fatal("expected session write failure") }
	assertBindings(t,f.o.output)
}
