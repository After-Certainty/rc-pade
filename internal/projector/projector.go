package projector

import (
	"fmt"
	"regexp"
	"strings"

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
		if err := projectCondition(condition, rule, capabilities); err != nil {
			return model.DevelopmentSession{}, err
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

func projectCondition(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest) error {
	hasOps := len(rule.Operations) > 0
	hasProject := len(rule.Project) > 0
	hasRequire := len(rule.Require) > 0
	hasCover := len(rule.Cover) > 0
	projectFamily := hasProject || hasRequire || hasCover

	if rule.OutsidePADE {
		if hasOps || projectFamily {
			return fmt.Errorf("projection rule for %s/%s sets outsidePADE with operations/project/require/cover; choose one classification", condition.Kind, condition.Interface.Type)
		}
		return nil
	}

	if hasOps && projectFamily {
		return fmt.Errorf("projection rule for %s/%s sets both operations and project/require/cover; choose one mechanism", condition.Kind, condition.Interface.Type)
	}

	if hasOps {
		return projectOperations(condition, rule, capabilities)
	}
	if hasProject {
		return projectFields(condition, rule, capabilities)
	}
	if projectFamily {
		return fmt.Errorf("projection rule for %s/%s sets require/cover without project", condition.Kind, condition.Interface.Type)
	}
	return fmt.Errorf("condition %s/%s matched a PADE-relevant rule with no operations or project clauses", condition.Kind, condition.Interface.Type)
}

func projectOperations(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest) error {
	if len(condition.Interface.Operations) == 0 {
		return fmt.Errorf("condition %s/%s has no operations; operations-backed rules require interface.operations[].name", condition.Kind, condition.Interface.Type)
	}

	for _, operation := range condition.Interface.Operations {
		mapping, ok := rule.Operations[operation.Name]
		if !ok {
			return fmt.Errorf("no projection for %s/%s operation %s", condition.Kind, condition.Interface.Type, operation.Name)
		}
		if mapping.Capability == "" {
			return fmt.Errorf("projection for %s/%s operation %s has an empty capability", condition.Kind, condition.Interface.Type, operation.Name)
		}
		if err := mergeCapability(capabilities, mapping.Capability, model.CapabilityRequest{
			Access:   mapping.Access,
			Required: !condition.Optional,
		}); err != nil {
			return err
		}
	}
	return nil
}

func projectFields(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest) error {
	for _, pred := range rule.Require {
		ok, err := evaluatePredicate(condition, pred)
		if err != nil {
			return fmt.Errorf("condition %s/%s require %s: %w", condition.Kind, condition.Interface.Type, pred.Path, err)
		}
		if !ok {
			return fmt.Errorf("condition %s/%s does not satisfy require %s", condition.Kind, condition.Interface.Type, describePredicate(pred))
		}
	}

	emittedForCondition := 0
	covered := map[string]map[string]bool{} // path -> value -> covered by firing clause

	for _, clause := range rule.Project {
		if clause.Capability == "" {
			return fmt.Errorf("projection rule for %s/%s has a project clause with an empty capability", condition.Kind, condition.Interface.Type)
		}
		satisfied := true
		for _, pred := range clause.When {
			ok, err := evaluatePredicate(condition, pred)
			if err != nil {
				return fmt.Errorf("condition %s/%s project when %s: %w", condition.Kind, condition.Interface.Type, pred.Path, err)
			}
			if !ok {
				satisfied = false
				break
			}
		}
		if !satisfied {
			continue
		}

		if err := mergeCapability(capabilities, clause.Capability, model.CapabilityRequest{
			Access:   clause.Access,
			Required: !condition.Optional,
		}); err != nil {
			return err
		}
		emittedForCondition++

		for _, pred := range clause.When {
			if pred.Contains == "" {
				continue
			}
			if covered[pred.Path] == nil {
				covered[pred.Path] = map[string]bool{}
			}
			covered[pred.Path][pred.Contains] = true
		}
	}

	for _, path := range rule.Cover {
		values, err := interfaceArrayStrings(condition, path)
		if err != nil {
			return fmt.Errorf("condition %s/%s cover %s: %w", condition.Kind, condition.Interface.Type, path, err)
		}
		if len(values) == 0 {
			return fmt.Errorf("condition %s/%s cover %s: array is missing or empty", condition.Kind, condition.Interface.Type, path)
		}
		for _, value := range values {
			if !covered[path][value] {
				return fmt.Errorf("condition %s/%s cover %s: value %q is not accounted for by any satisfied project clause", condition.Kind, condition.Interface.Type, path, value)
			}
		}
	}

	if emittedForCondition == 0 {
		return fmt.Errorf("condition %s/%s matched a project rule but emitted no capabilities; use outsidePADE to accept with none", condition.Kind, condition.Interface.Type)
	}
	return nil
}

func mergeCapability(capabilities map[string]model.CapabilityRequest, name string, request model.CapabilityRequest) error {
	if existing, exists := capabilities[name]; exists {
		if existing.Access != request.Access {
			return fmt.Errorf("capability %s is projected with conflicting access values %q and %q", name, existing.Access, request.Access)
		}
		request.Required = existing.Required || request.Required
	}
	capabilities[name] = request
	return nil
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

func evaluatePredicate(condition model.Condition, pred model.FieldPredicate) (bool, error) {
	if pred.Path == "" {
		return false, fmt.Errorf("path is required")
	}
	hasEquals := pred.Equals != ""
	hasContains := pred.Contains != ""
	if hasEquals == hasContains {
		return false, fmt.Errorf("exactly one of equals or contains is required")
	}

	value, err := lookupInterfaceField(condition, pred.Path)
	if err != nil {
		return false, err
	}
	if value == nil {
		// Missing field fails the predicate without a type error.
		return false, nil
	}
	if hasEquals {
		got, ok := value.(string)
		if !ok {
			return false, fmt.Errorf("equals requires a string value at %s", pred.Path)
		}
		return got == pred.Equals, nil
	}

	items, err := asStringSlice(value)
	if err != nil {
		return false, fmt.Errorf("contains requires a string array at %s: %w", pred.Path, err)
	}
	for _, item := range items {
		if item == pred.Contains {
			return true, nil
		}
	}
	return false, nil
}

func interfaceArrayStrings(condition model.Condition, path string) ([]string, error) {
	value, err := lookupInterfaceField(condition, path)
	if err != nil {
		return nil, err
	}
	if value == nil {
		return nil, nil
	}
	return asStringSlice(value)
}

func lookupInterfaceField(condition model.Condition, path string) (any, error) {
	const prefix = "interface."
	if !strings.HasPrefix(path, prefix) {
		return nil, fmt.Errorf("path %q must start with interface.", path)
	}
	field := strings.TrimPrefix(path, prefix)
	if field == "" || strings.Contains(field, ".") {
		return nil, fmt.Errorf("path %q must be interface.<field> with a single top-level field", path)
	}
	if condition.Interface.Fields == nil {
		return nil, fmt.Errorf("interface fields are unavailable")
	}
	value, ok := condition.Interface.Fields[field]
	if !ok {
		return nil, nil
	}
	return value, nil
}

func asStringSlice(value any) ([]string, error) {
	switch typed := value.(type) {
	case []string:
		return typed, nil
	case []any:
		out := make([]string, 0, len(typed))
		for i, item := range typed {
			s, ok := item.(string)
			if !ok {
				return nil, fmt.Errorf("element %d is not a string", i)
			}
			out = append(out, s)
		}
		return out, nil
	default:
		return nil, fmt.Errorf("value is %T, not a string array", value)
	}
}

func describePredicate(pred model.FieldPredicate) string {
	if pred.Equals != "" {
		return fmt.Sprintf("%s equals %q", pred.Path, pred.Equals)
	}
	return fmt.Sprintf("%s contains %q", pred.Path, pred.Contains)
}
