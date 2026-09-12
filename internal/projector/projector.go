package projector

import (
	"fmt"
	"regexp"

	"github.com/After-Certainty/rc-pade/internal/model"
)

var padeNamePattern = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$`)

func Project(profile model.RuntimeConditionsProfile, policy model.ProjectionPolicy, nameOverride string) (model.DevelopmentSession, error) {
	if profile.APIVersion != model.RuntimeConditionsAPIVersion || profile.Kind != model.RuntimeConditionsKind {
		return model.DevelopmentSession{}, fmt.Errorf("unsupported Runtime Conditions document %q %q", profile.APIVersion, profile.Kind)
	}
	if policy.APIVersion != model.ProjectionPolicyAPIVersion || policy.Kind != model.ProjectionPolicyKind {
		return model.DevelopmentSession{}, fmt.Errorf("unsupported projection policy %q %q", policy.APIVersion, policy.Kind)
	}

	name := nameOverride
	if name == "" {
		name = profile.Metadata.Name
	}
	if name == "" || len(name) > 253 || !padeNamePattern.MatchString(name) {
		return model.DevelopmentSession{}, fmt.Errorf("PADE metadata.name %q is not a valid DNS-1123-style name; use --name to override it", name)
	}

	capabilities := map[string]model.CapabilityRequest{}
	for _, condition := range profile.Conditions {
		rule, err := matchingRule(policy.Rules, condition)
		if err != nil {
			return model.DevelopmentSession{}, err
		}
		if len(condition.Interface.Operations) == 0 {
			return model.DevelopmentSession{}, fmt.Errorf("condition %s/%s has no operations; the initial experiment only projects operation-backed conditions", condition.Kind, condition.Interface.Type)
		}

		for _, operation := range condition.Interface.Operations {
			mapping, ok := rule.Operations[operation.Name]
			if !ok {
				return model.DevelopmentSession{}, fmt.Errorf("no projection for %s/%s operation %s", condition.Kind, condition.Interface.Type, operation.Name)
			}
			if mapping.Capability == "" {
				return model.DevelopmentSession{}, fmt.Errorf("projection for %s/%s operation %s has an empty capability", condition.Kind, condition.Interface.Type, operation.Name)
			}

			request := model.CapabilityRequest{
				Access:   mapping.Access,
				Required: !condition.Optional,
			}
			if existing, exists := capabilities[mapping.Capability]; exists {
				if existing.Access != request.Access {
					return model.DevelopmentSession{}, fmt.Errorf("capability %s is projected with conflicting access values %q and %q", mapping.Capability, existing.Access, request.Access)
				}
				request.Required = existing.Required || request.Required
			}
			capabilities[mapping.Capability] = request
		}
	}

	annotations := map[string]string{
		"rc-pade.local/source-profile": profile.Metadata.Name,
	}
	if profile.Workload.URI != "" {
		annotations["rc-pade.local/source-workload-uri"] = profile.Workload.URI
	}
	if profile.Workload.Version != "" {
		annotations["rc-pade.local/source-workload-version"] = profile.Workload.Version
	}

	return model.DevelopmentSession{
		APIVersion: model.PADEAPIVersion,
		Kind:       model.PADEKind,
		Metadata: model.PADEMetadata{
			Name:        name,
			Annotations: annotations,
		},
		Spec: model.PADESpec{Capabilities: capabilities},
	}, nil
}

func matchingRule(rules []model.ProjectionRule, condition model.Condition) (model.ProjectionRule, error) {
	var match *model.ProjectionRule
	for i := range rules {
		rule := &rules[i]
		if rule.Match.Kind != condition.Kind || rule.Match.InterfaceType != condition.Interface.Type {
			continue
		}
		if match != nil {
			return model.ProjectionRule{}, fmt.Errorf("multiple projection rules match %s/%s", condition.Kind, condition.Interface.Type)
		}
		match = rule
	}
	if match == nil {
		return model.ProjectionRule{}, fmt.Errorf("no projection rule matches %s/%s", condition.Kind, condition.Interface.Type)
	}
	return *match, nil
}
