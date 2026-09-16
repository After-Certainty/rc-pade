package projector

import (
	"strings"
	"testing"

	"github.com/After-Certainty/rc-pade/internal/model"
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
	if err == nil || !strings.Contains(err.Error(), "no projection rule matches api/http") {
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
	if err == nil || !strings.Contains(err.Error(), "outsidePADE and operations") {
		t.Fatalf("expected conflicting classification error, got %v", err)
	}
}

func TestPADERelevantWithoutOperationsFailsExplicitly(t *testing.T) {
	profile := model.RuntimeConditionsProfile{
		APIVersion: model.RuntimeConditionsAPIVersion,
		Kind:       model.RuntimeConditionsKind,
		Metadata:   model.RCMetadata{Name: "source-control-only"},
		Conditions: []model.Condition{{
			Kind: "source_control",
			Interface: model.RCInterface{
				Type: "git",
				// Real composed profiles carry access/provider, not operations[].name.
			},
		}},
	}
	policy := model.ProjectionPolicy{
		APIVersion: model.ProjectionPolicyAPIVersion,
		Kind:       model.ProjectionPolicyKind,
		Rules: []model.ProjectionRule{{
			Match: model.ConditionMatch{Kind: "source_control", InterfaceType: "git"},
			// Matched and in-scope for PADE, but not representable as operations yet.
		}},
	}

	_, err := Project(profile, policy, "")
	if err == nil || !strings.Contains(err.Error(), "has no operations") {
		t.Fatalf("expected no-operations projection failure, got %v", err)
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
