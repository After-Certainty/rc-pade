package projector

import (
	"strings"
	"testing"

	"github.com/After-Certainty/rc-pade/internal/model"
)

func TestOptionalUnsupportedFailsClosedByDefault(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "opt-unsupported"},
		Conditions: []model.Condition{
			s3Profile(false).Conditions[0],
			{
				Optional: true,
				Kind:     "api",
				Interface: model.RCInterface{
					Type:   "http",
					Fields: map[string]any{"type": "http"},
				},
			},
		},
	}

	session, report, err := ProjectWithSupport(profile, s3Policy(), "")
	if err == nil {
		t.Fatalf("expected fail-closed, got session %#v", session)
	}
	if !strings.Contains(err.Error(), "no projection rule matches") {
		t.Fatalf("error = %v", err)
	}
	if len(report.Conditions) != 2 {
		t.Fatalf("report conditions = %#v", report.Conditions)
	}
	if report.Conditions[0].Outcome != model.SupportSupportedProjected {
		t.Fatalf("first outcome = %s", report.Conditions[0].Outcome)
	}
	if report.Conditions[1].Outcome != model.SupportUnsupportedOptional {
		t.Fatalf("second outcome = %s", report.Conditions[1].Outcome)
	}
	if report.ContinuedDespiteUnsupportedOptional {
		t.Fatal("default path must not continue")
	}
}

func TestOptionalUnsupportedContinuesUnderOperatorPolicy(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "opt-continue"},
		Conditions: []model.Condition{
			s3Profile(false).Conditions[0],
			{
				Optional: true,
				Kind:     "api",
				Interface: model.RCInterface{
					Type:   "http",
					Fields: map[string]any{"type": "http"},
				},
			},
		},
	}
	policy := s3Policy()
	policy.OnUnsupportedOptional = model.UnsupportedOptionalContinue

	session, report, err := ProjectWithSupport(profile, policy, "")
	if err != nil {
		t.Fatalf("ProjectWithSupport() error = %v", err)
	}
	if len(session.Spec.Capabilities) != 1 {
		t.Fatalf("capabilities = %#v", session.Spec.Capabilities)
	}
	assertCap(t, session, "aws.s3.bucket.write", "write", true)
	if !report.ContinuedDespiteUnsupportedOptional {
		t.Fatal("expected continuedDespiteUnsupportedOptional")
	}
	if report.Conditions[1].Outcome != model.SupportUnsupportedOptional {
		t.Fatalf("outcome = %s", report.Conditions[1].Outcome)
	}
}

func TestRequiredUnsupportedStillFailsWithContinuePolicy(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "req-unsupported"},
		Conditions: []model.Condition{{
			Kind: "api",
			Interface: model.RCInterface{
				Type:   "http",
				Fields: map[string]any{"type": "http"},
			},
		}},
	}
	policy := s3Policy()
	policy.OnUnsupportedOptional = model.UnsupportedOptionalContinue

	_, report, err := ProjectWithSupport(profile, policy, "")
	if err == nil {
		t.Fatal("required unmatched must fail closed")
	}
	if report.Conditions[0].Outcome != model.SupportUnsupportedRequired {
		t.Fatalf("outcome = %s", report.Conditions[0].Outcome)
	}
}

func TestOptionalSupportedPreservesRequiredFalse(t *testing.T) {
	session, report, err := ProjectWithSupport(s3Profile(true), s3Policy(), "")
	if err != nil {
		t.Fatalf("ProjectWithSupport() error = %v", err)
	}
	assertCap(t, session, "aws.s3.bucket.write", "write", false)
	if report.Conditions[0].Outcome != model.SupportSupportedProjected {
		t.Fatalf("outcome = %s", report.Conditions[0].Outcome)
	}
	if len(report.Conditions[0].Capabilities) != 1 || report.Conditions[0].Capabilities[0] != "aws.s3.bucket.write" {
		t.Fatalf("capabilities = %#v", report.Conditions[0].Capabilities)
	}
}

func TestOutsidePADERecordedInSupportReport(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "outside"},
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
	session, report, err := ProjectWithSupport(profile, policy, "")
	if err != nil {
		t.Fatalf("ProjectWithSupport() error = %v", err)
	}
	if len(session.Spec.Capabilities) != 0 {
		t.Fatalf("capabilities = %#v", session.Spec.Capabilities)
	}
	if report.Conditions[0].Outcome != model.SupportOutsidePADE {
		t.Fatalf("outcome = %s", report.Conditions[0].Outcome)
	}
}

func TestProjectionPolicyErrorDistinctFromUnsupported(t *testing.T) {
	_, report, err := ProjectWithSupport(gitProfile(false, "gitlab", []string{"fetch"}), gitPolicy(), "")
	if err == nil {
		t.Fatal("expected require failure")
	}
	if report.Conditions[0].Outcome != model.SupportProjectionError {
		t.Fatalf("outcome = %s detail=%s", report.Conditions[0].Outcome, report.Conditions[0].Detail)
	}
}

func TestMultipleConditionsMixedOptionalContinue(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "mixed"},
		Conditions: []model.Condition{
			gitProfile(false, "github", []string{"fetch", "push"}).Conditions[0],
			{
				Optional: true,
				Kind:     "cache",
				Interface: model.RCInterface{
					Type:   "key_value",
					Fields: map[string]any{"type": "key_value"},
				},
			},
			s3Profile(true).Conditions[0],
		},
	}
	policy := gitPolicy()
	policy.OnUnsupportedOptional = model.UnsupportedOptionalContinue
	policy.Rules = append(policy.Rules, s3Policy().Rules...)

	session, report, err := ProjectWithSupport(profile, policy, "")
	if err != nil {
		t.Fatalf("ProjectWithSupport() error = %v", err)
	}
	assertCap(t, session, "github.repo.read", "read", true)
	assertCap(t, session, "github.repo.write", "write", true)
	assertCap(t, session, "aws.s3.bucket.write", "write", false)
	if len(session.Spec.Capabilities) != 3 {
		t.Fatalf("capabilities = %#v", session.Spec.Capabilities)
	}
	if report.Conditions[0].Outcome != model.SupportSupportedProjected {
		t.Fatalf("git outcome = %s", report.Conditions[0].Outcome)
	}
	if report.Conditions[1].Outcome != model.SupportUnsupportedOptional {
		t.Fatalf("cache outcome = %s", report.Conditions[1].Outcome)
	}
	if report.Conditions[2].Outcome != model.SupportSupportedProjected {
		t.Fatalf("s3 outcome = %s", report.Conditions[2].Outcome)
	}
	if !report.ContinuedDespiteUnsupportedOptional {
		t.Fatal("expected continue flag")
	}
}

func TestConflictingMappingsRemainProjectionErrors(t *testing.T) {
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
	_, report, err := ProjectWithSupport(gitProfile(false, "github", []string{"fetch", "pull"}), policy, "")
	if err == nil || !strings.Contains(err.Error(), "conflicting access") {
		t.Fatalf("expected conflicting access, got %v", err)
	}
	if report.Conditions[0].Outcome != model.SupportProjectionError {
		t.Fatalf("outcome = %s", report.Conditions[0].Outcome)
	}
}

func TestInvalidOnUnsupportedOptionalRejected(t *testing.T) {
	policy := s3Policy()
	policy.OnUnsupportedOptional = "skip"
	_, _, err := ProjectWithSupport(s3Profile(false), policy, "")
	if err == nil || !strings.Contains(err.Error(), "onUnsupportedOptional") {
		t.Fatalf("expected invalid mode error, got %v", err)
	}
}
