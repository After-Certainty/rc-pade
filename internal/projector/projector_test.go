package projector

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/After-Certainty/rc-pade/internal/model"
	"gopkg.in/yaml.v3"
)

func TestProjectS3PutObject(t *testing.T) {
	profile := s3Profile(false)
	policy := s3Policy()

	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}

	capability, ok := got.Spec.Capabilities["aws.s3.bucket.write"]
	if !ok {
		t.Fatalf("expected aws.s3.bucket.write capability, got %#v", got.Spec.Capabilities)
	}
	if capability.Access != "write" || !capability.Required {
		t.Fatalf("unexpected capability: %#v", capability)
	}
	if got.Metadata.Annotations["rc-pade.local/source-workload-uri"] != "file://./examples/s3-put-object/app" {
		t.Fatalf("workload URI provenance not preserved")
	}
}

func TestOptionalConditionProjectsToOptionalCapability(t *testing.T) {
	got, err := Project(s3Profile(true), s3Policy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if got.Spec.Capabilities["aws.s3.bucket.write"].Required {
		t.Fatal("optional RC condition should produce required: false")
	}
}

func TestUnmappedOperationFailsClosed(t *testing.T) {
	profile := s3Profile(false)
	profile.Conditions[0].Interface.Operations[0].Name = "GetObject"

	_, err := Project(profile, s3Policy(), "")
	if err == nil || !strings.Contains(err.Error(), "no projection") {
		t.Fatalf("expected no projection error, got %v", err)
	}
}

func TestUnmatchedConditionFailsClosed(t *testing.T) {
	profile := s3Profile(false)
	profile.Conditions = append(profile.Conditions, model.Condition{
		Kind: "api",
		Interface: model.RCInterface{
			Type: "http",
		},
	})

	_, err := Project(profile, s3Policy(), "")
	if err == nil || !strings.Contains(err.Error(), "no projection rule matches") || !strings.Contains(err.Error(), "api/http") {
		t.Fatalf("expected unmatched api/http error, got %v", err)
	}
}

func TestOutsidePADEEmitsNoCapability(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "mixed-profile"},
		Conditions: []model.Condition{
			{
				Kind: "api",
				Interface: model.RCInterface{
					Type: "http",
					Operations: []model.Operation{
						{Name: "ignored-because-outside"},
					},
				},
			},
			s3Profile(false).Conditions[0],
		},
	}
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{
			{
				Match:       model.ConditionMatch{Kind: "api", InterfaceType: "http"},
				OutsidePADE: true,
			},
			s3Policy().Rules[0],
		},
	}

	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 1 {
		t.Fatalf("expected only S3 capability, got %#v", got.Spec.Capabilities)
	}
	if _, ok := got.Spec.Capabilities["aws.s3.bucket.write"]; !ok {
		t.Fatalf("expected aws.s3.bucket.write, got %#v", got.Spec.Capabilities)
	}
}

func TestOutsidePADEWithOperationsRejected(t *testing.T) {
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match:       model.ConditionMatch{Kind: "api", InterfaceType: "http"},
			OutsidePADE: true,
			Operations: map[string]model.OperationMapping{
				"GET": {Capability: "should.not.matter"},
			},
		}},
	}
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "http-only"},
		Conditions: []model.Condition{{
			Kind:      "api",
			Interface: model.RCInterface{Type: "http"},
		}},
	}

	_, err := Project(profile, policy, "")
	if err == nil || !strings.Contains(err.Error(), "outsidePADE") {
		t.Fatalf("expected conflicting classification error, got %v", err)
	}
}

func TestPADERelevantWithoutProjectionMechanismFailsExplicitly(t *testing.T) {
	profile := gitProfile(false, "github", []string{"fetch"})
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
		}},
	}

	_, err := Project(profile, policy, "")
	if err == nil || !strings.Contains(err.Error(), "no operations or project") {
		t.Fatalf("expected missing projection mechanism error, got %v", err)
	}
}

func TestGitFetchPullPushProjectsReadAndWrite(t *testing.T) {
	got, err := Project(gitProfile(false, "github", []string{"fetch", "pull", "push"}), gitPolicy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 2 {
		t.Fatalf("expected 2 capabilities, got %#v", got.Spec.Capabilities)
	}
	assertCap(t, got, "github.repo.read", "read", true)
	assertCap(t, got, "github.repo.write", "write", true)
}

func TestGitFetchAndPullCoalesceToOneRead(t *testing.T) {
	got, err := Project(gitProfile(false, "github", []string{"fetch", "pull"}), gitPolicy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 1 {
		t.Fatalf("expected single capability, got %#v", got.Spec.Capabilities)
	}
	assertCap(t, got, "github.repo.read", "read", true)
}

func TestGitFetchOnlyProjectsRead(t *testing.T) {
	got, err := Project(gitProfile(false, "github", []string{"fetch"}), gitPolicy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if _, ok := got.Spec.Capabilities["github.repo.write"]; ok {
		t.Fatalf("did not expect write: %#v", got.Spec.Capabilities)
	}
	assertCap(t, got, "github.repo.read", "read", true)
}

func TestGitPushOnlyProjectsWrite(t *testing.T) {
	got, err := Project(gitProfile(false, "github", []string{"push"}), gitPolicy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if _, ok := got.Spec.Capabilities["github.repo.read"]; ok {
		t.Fatalf("did not expect read: %#v", got.Spec.Capabilities)
	}
	assertCap(t, got, "github.repo.write", "write", true)
}

func TestGitUnknownAccessFailsCover(t *testing.T) {
	_, err := Project(gitProfile(false, "github", []string{"fetch", "pull", "push", "rebase"}), gitPolicy(), "")
	if err == nil || !strings.Contains(err.Error(), "not accounted for") {
		t.Fatalf("expected cover failure, got %v", err)
	}
}

func TestGitProviderMismatchFailsRequire(t *testing.T) {
	_, err := Project(gitProfile(false, "gitlab", []string{"fetch"}), gitPolicy(), "")
	if err == nil || !strings.Contains(err.Error(), "does not satisfy require") {
		t.Fatalf("expected require failure, got %v", err)
	}
}

func TestGitMissingProviderFailsRequire(t *testing.T) {
	profile := gitProfile(false, "github", []string{"fetch"})
	delete(profile.Conditions[0].Interface.Fields, "provider")
	_, err := Project(profile, gitPolicy(), "")
	if err == nil || !strings.Contains(err.Error(), "does not satisfy require") {
		t.Fatalf("expected missing provider failure, got %v", err)
	}
}

func TestGitMissingAccessFailsCover(t *testing.T) {
	profile := gitProfile(false, "github", []string{"fetch"})
	delete(profile.Conditions[0].Interface.Fields, "access")
	_, err := Project(profile, gitPolicy(), "")
	if err == nil || !strings.Contains(err.Error(), "cover") {
		t.Fatalf("expected cover failure for missing access, got %v", err)
	}
}

func TestHTTPOutsidePADEAcceptsNoCapability(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "http-only"},
		Conditions: []model.Condition{{
			Kind: "api",
			Interface: model.RCInterface{
				Type:   "http",
				Fields: map[string]any{"type": "http"},
			},
		}},
	}
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match:       model.ConditionMatch{Kind: "api", InterfaceType: "http"},
			OutsidePADE: true,
		}},
	}
	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 0 {
		t.Fatalf("expected no capabilities, got %#v", got.Spec.Capabilities)
	}
}

func TestAnalyticsOutsidePADEAcceptsNoCapability(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "analytics-only"},
		Conditions: []model.Condition{{
			Kind: "google.analytics",
			Interface: model.RCInterface{
				Type:   "web",
				Fields: map[string]any{"type": "web", "events": []any{"page_view"}},
			},
		}},
	}
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match:       model.ConditionMatch{Kind: "google.analytics", InterfaceType: "web"},
			OutsidePADE: true,
		}},
	}
	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 0 {
		t.Fatalf("expected no capabilities, got %#v", got.Spec.Capabilities)
	}
}

func TestMultipleTopLevelRulesAmbiguous(t *testing.T) {
	policy := gitPolicy()
	policy.Rules = append(policy.Rules, model.ProjectionRule{
		Match:       model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
		OutsidePADE: true,
	})
	_, err := Project(gitProfile(false, "github", []string{"fetch"}), policy, "")
	if err == nil || !strings.Contains(err.Error(), "multiple projection rules match") {
		t.Fatalf("expected ambiguous match error, got %v", err)
	}
}

func TestOutsidePADEWithProjectRejected(t *testing.T) {
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match:       model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
			OutsidePADE: true,
			Project: []model.ProjectClause{{
				When:       []model.FieldPredicate{{Path: "interface.access", Contains: "fetch"}},
				Capability: "github.repo.read",
				Access:     "read",
			}},
		}},
	}
	_, err := Project(gitProfile(false, "github", []string{"fetch"}), policy, "")
	if err == nil || !strings.Contains(err.Error(), "outsidePADE") {
		t.Fatalf("expected outsidePADE+project error, got %v", err)
	}
}

func TestConflictingCapabilityAccessFails(t *testing.T) {
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
			Require: []model.FieldPredicate{
				{Path: "interface.provider", Equals: "github"},
			},
			Project: []model.ProjectClause{
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "fetch"}},
					Capability: "github.repo.read",
					Access:     "read",
				},
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "pull"}},
					Capability: "github.repo.read",
					Access:     "write",
				},
			},
			Cover: []string{"interface.access"},
		}},
	}
	_, err := Project(gitProfile(false, "github", []string{"fetch", "pull"}), policy, "")
	if err == nil || !strings.Contains(err.Error(), "conflicting access") {
		t.Fatalf("expected conflicting access error, got %v", err)
	}
}

func TestOptionalGitFetchProjectsRequiredFalse(t *testing.T) {
	got, err := Project(gitProfile(true, "github", []string{"fetch"}), gitPolicy(), "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	assertCap(t, got, "github.repo.read", "read", false)
}

func TestPublishedRequestLoggerOutsidePADE(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	root := filepath.Join(filepath.Dir(thisFile), "..", "..", "testdata", "published")
	profileRaw, err := os.ReadFile(filepath.Join(root, "request-logger-http.profile.yaml"))
	if err != nil {
		t.Fatalf("read profile: %v", err)
	}
	policyRaw, err := os.ReadFile(filepath.Join(root, "request-logger-outside-pade.policy.yaml"))
	if err != nil {
		t.Fatalf("read policy: %v", err)
	}

	var profile model.RuntimeConditionsProfile
	if err := yaml.Unmarshal(profileRaw, &profile); err != nil {
		t.Fatalf("unmarshal profile: %v", err)
	}
	var policy model.ProjectionPolicy
	if err := yaml.Unmarshal(policyRaw, &policy); err != nil {
		t.Fatalf("unmarshal policy: %v", err)
	}

	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 0 {
		t.Fatalf("published request-logger demand is outside PADE; expected zero capabilities, got %#v", got.Spec.Capabilities)
	}
	if got.Metadata.Annotations["rc-pade.local/source-profile"] != "request-logger-http" {
		t.Fatalf("source-profile annotation = %#v", got.Metadata.Annotations)
	}
}

func TestPublishedRequestLoggerUnsupportedWithoutPolicy(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	path := filepath.Join(filepath.Dir(thisFile), "..", "..", "testdata", "published", "request-logger-http.profile.yaml")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read profile: %v", err)
	}
	var profile model.RuntimeConditionsProfile
	if err := yaml.Unmarshal(raw, &profile); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	_, err = Project(profile, s3Policy(), "")
	if err == nil {
		t.Fatal("expected unsupported platform-support failure")
	}
	if !strings.Contains(err.Error(), "no projection rule matches") {
		t.Fatalf("expected unmatched rule error, got %v", err)
	}
	if !strings.Contains(err.Error(), "condition[0]") {
		t.Fatalf("expected local reporting label for unnamed condition, got %v", err)
	}
	if !strings.Contains(err.Error(), "api/http") {
		t.Fatalf("expected kind/type in error, got %v", err)
	}
}

func TestNamedConditionLabelInUnsupportedError(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "named-unsupported"},
		Conditions: []model.Condition{{
			Name: "todos-api",
			Kind: "api",
			Interface: model.RCInterface{
				Type:   "http",
				Fields: map[string]any{"type": "http"},
			},
		}},
	}
	_, err := Project(profile, s3Policy(), "")
	if err == nil || !strings.Contains(err.Error(), "todos-api") {
		t.Fatalf("expected named condition label in error, got %v", err)
	}
}

func TestCacheOutsidePADEAcceptsNoCapability(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "cache-only"},
		Conditions: []model.Condition{{
			Kind: "cache",
			Interface: model.RCInterface{
				Type:   "key_value",
				Fields: map[string]any{"type": "key_value", "engine": "redis"},
			},
			Configuration: map[string]any{
				"alternatives": []any{
					map[string]any{"env": []any{map[string]any{"name": "REDIS_URL", "property": "url"}}},
				},
			},
		}},
	}
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match:       model.ConditionMatch{Kind: "cache", InterfaceType: "key_value"},
			OutsidePADE: true,
		}},
	}
	got, err := Project(profile, policy, "")
	if err != nil {
		t.Fatalf("Project() error = %v", err)
	}
	if len(got.Spec.Capabilities) != 0 {
		t.Fatalf("expected no capabilities, got %#v", got.Spec.Capabilities)
	}
}

func TestProjectModeZeroEmissionFails(t *testing.T) {
	// Clause when can never fire (contains a value not in access), but cover
	// is empty so we would otherwise emit nothing after require succeeds.
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
			Require: []model.FieldPredicate{
				{Path: "interface.provider", Equals: "github"},
			},
			Project: []model.ProjectClause{{
				When:       []model.FieldPredicate{{Path: "interface.access", Contains: "clone"}},
				Capability: "github.repo.read",
				Access:     "read",
			}},
			// No cover: empty access cover would fail first; omit cover to hit zero-emission.
		}},
	}
	profile := gitProfile(false, "github", []string{"fetch"})
	_, err := Project(profile, policy, "")
	if err == nil || !strings.Contains(err.Error(), "emitted no capabilities") {
		t.Fatalf("expected zero-emission failure, got %v", err)
	}
}

func assertCap(t *testing.T, session model.DevelopmentSession, name, access string, required bool) {
	t.Helper()
	cap, ok := session.Spec.Capabilities[name]
	if !ok {
		t.Fatalf("missing capability %s in %#v", name, session.Spec.Capabilities)
	}
	if cap.Access != access || cap.Required != required {
		t.Fatalf("capability %s = %#v, want access=%s required=%v", name, cap, access, required)
	}
}

func gitProfile(optional bool, provider string, access []string) model.RuntimeConditionsProfile {
	accessAny := make([]any, len(access))
	for i, v := range access {
		accessAny[i] = v
	}
	fields := map[string]any{
		"type": "git",
	}
	if provider != "" {
		fields["provider"] = provider
	}
	if access != nil {
		fields["access"] = accessAny
	}
	return model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "git-profile"},
		Conditions: []model.Condition{{
			Optional: optional,
			Kind:     "source_control",
			Interface: model.RCInterface{
				Type:   "git",
				Fields: fields,
			},
		}},
	}
}

func gitPolicy() model.ProjectionPolicy {
	return model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
			Require: []model.FieldPredicate{
				{Path: "interface.provider", Equals: "github"},
			},
			Project: []model.ProjectClause{
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "fetch"}},
					Capability: "github.repo.read",
					Access:     "read",
				},
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "pull"}},
					Capability: "github.repo.read",
					Access:     "read",
				},
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "push"}},
					Capability: "github.repo.write",
					Access:     "write",
				},
				{
					When:       []model.FieldPredicate{{Path: "interface.access", Contains: "clone"}},
					Capability: "github.repo.read",
					Access:     "read",
				},
			},
			Cover: []string{"interface.access"},
		}},
	}
}

func s3Profile(optional bool) model.RuntimeConditionsProfile {
	return model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "s3-put-object"},
		Workload:   model.Workload{URI: "file://./examples/s3-put-object/app", Version: "0.0.1"},
		Conditions: []model.Condition{{
			Optional: optional,
			Kind:     "aws.s3",
			Interface: model.RCInterface{
				Type:       "bucket",
				Operations: []model.Operation{{Name: "PutObject"}},
				Fields: map[string]any{
					"type": "bucket",
					"operations": []any{
						map[string]any{"name": "PutObject"},
					},
				},
			},
		}},
	}
}

func s3Policy() model.ProjectionPolicy {
	return model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "aws.s3", InterfaceType: "bucket"},
			Operations: map[string]model.OperationMapping{
				"PutObject": {Capability: "aws.s3.bucket.write", Access: "write"},
			},
		}},
	}
}
