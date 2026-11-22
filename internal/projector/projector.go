package projector

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/After-Certainty/rc-pade/internal/model"
)

var padeNamePattern = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$`)

// Project projects a verified Runtime Conditions Profile under operator policy.
// It rejects onUnsupportedOptional: continue so unsupported optional outcomes
// cannot be discarded by callers that ignore the support report. Use
// ProjectWithSupport when continuation is configured.
func Project(profile model.RuntimeConditionsProfile, policy model.ProjectionPolicy, nameOverride string) (model.DevelopmentSession, error) {
	if policy.OnUnsupportedOptional == model.UnsupportedOptionalContinue {
		return model.DevelopmentSession{}, fmt.Errorf("onUnsupportedOptional %q requires ProjectWithSupport so unsupported optional outcomes are not discarded", model.UnsupportedOptionalContinue)
	}
	session, _, err := ProjectWithSupport(profile, policy, nameOverride)
	return session, err
}

// ProjectWithSupport projects a Profile and returns a local PlatformSupportReport.
// The report is an rc-pade platform-support artifact, not an upstream Runtime
// Conditions validation or authorization standard.
func ProjectWithSupport(profile model.RuntimeConditionsProfile, policy model.ProjectionPolicy, nameOverride string) (model.DevelopmentSession, model.PlatformSupportReport, error) {
	report := model.PlatformSupportReport{
		APIVersion: model.SupportAPIVersion,
		Kind:       model.SupportKind,
		Profile:    profile.Metadata.Name,
		Conditions: []model.ConditionSupportResult{},
	}

	if profile.APIVersion != model.RuntimeConditionsAPIVersion || profile.Kind != model.RuntimeConditionsKind {
		return model.DevelopmentSession{}, report, fmt.Errorf("unsupported Runtime Conditions document %q %q", profile.APIVersion, profile.Kind)
	}
	if policy.APIVersion != model.ProjectionPolicyAPIVersion || policy.Kind != model.ProjectionPolicyKind {
		return model.DevelopmentSession{}, report, fmt.Errorf("unsupported projection policy %q %q", policy.APIVersion, policy.Kind)
	}
	if err := validateUnsupportedOptionalMode(policy.OnUnsupportedOptional); err != nil {
		return model.DevelopmentSession{}, report, err
	}

	name := nameOverride
	if name == "" {
		name = profile.Metadata.Name
	}
	if name == "" || len(name) > 253 || !padeNamePattern.MatchString(name) {
		return model.DevelopmentSession{}, report, fmt.Errorf("PADE metadata.name %q is not a valid DNS-1123-style name; use --name to override it", name)
	}

	capabilities := map[string]model.CapabilityRequest{}
	continueOptional := policy.OnUnsupportedOptional == model.UnsupportedOptionalContinue

	for i, condition := range profile.Conditions {
		entry := baseSupportEntry(condition, i)
		rule, found, err := findMatchingRule(policy.Rules, condition, i)
		if err != nil {
			entry.Outcome = model.SupportProjectionError
			entry.Detail = err.Error()
			report.Conditions = append(report.Conditions, entry)
			return model.DevelopmentSession{}, report, err
		}
		if !found {
			if condition.Optional {
				entry.Outcome = model.SupportUnsupportedOptional
				entry.Detail = fmt.Sprintf("no projection rule matches %s (%s/%s)", entry.Label, condition.Kind, condition.Interface.Type)
				report.Conditions = append(report.Conditions, entry)
				if continueOptional {
					report.ContinuedDespiteUnsupportedOptional = true
					continue
				}
				return model.DevelopmentSession{}, report, fmt.Errorf("%s", entry.Detail)
			}
			entry.Outcome = model.SupportUnsupportedRequired
			entry.Detail = fmt.Sprintf("no projection rule matches %s (%s/%s)", entry.Label, condition.Kind, condition.Interface.Type)
			report.Conditions = append(report.Conditions, entry)
			return model.DevelopmentSession{}, report, fmt.Errorf("%s", entry.Detail)
		}

		caps, outside, err := projectCondition(condition, rule, capabilities, i)
		if err != nil {
			entry.Outcome = model.SupportProjectionError
			entry.Detail = err.Error()
			report.Conditions = append(report.Conditions, entry)
			return model.DevelopmentSession{}, report, err
		}
		if outside {
			entry.Outcome = model.SupportOutsidePADE
			entry.Detail = "classified outsidePADE by operator projection policy"
			report.Conditions = append(report.Conditions, entry)
			continue
		}
		entry.Outcome = model.SupportSupportedProjected
		entry.Capabilities = caps
		report.Conditions = append(report.Conditions, entry)
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

	report.Complete = true
	return model.DevelopmentSession{
		APIVersion: model.PADEAPIVersion,
		Kind:       model.PADEKind,
		Metadata: model.PADEMetadata{
			Name:        name,
			Annotations: annotations,
		},
		Spec: model.PADESpec{Capabilities: capabilities},
	}, report, nil
}

func validateUnsupportedOptionalMode(mode string) error {
	switch mode {
	case "", model.UnsupportedOptionalFail, model.UnsupportedOptionalContinue:
		return nil
	default:
		return fmt.Errorf("onUnsupportedOptional must be %q or %q, got %q", model.UnsupportedOptionalFail, model.UnsupportedOptionalContinue, mode)
	}
}

func baseSupportEntry(condition model.Condition, index int) model.ConditionSupportResult {
	return model.ConditionSupportResult{
		Index:         index,
		Label:         model.ConditionLabel(condition, index),
		Name:          condition.Name,
		Kind:          condition.Kind,
		InterfaceType: condition.Interface.Type,
		Optional:      condition.Optional,
	}
}

func projectCondition(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest, index int) (caps []string, outside bool, err error) {
	label := model.ConditionLabel(condition, index)
	hasOps := len(rule.Operations) > 0
	hasProject := len(rule.Project) > 0
	hasRequire := len(rule.Require) > 0
	hasCover := len(rule.Cover) > 0
	projectFamily := hasProject || hasRequire || hasCover

	if rule.OutsidePADE {
		if hasOps || projectFamily {
			return nil, false, fmt.Errorf("projection rule for %s (%s/%s) sets outsidePADE with operations/project/require/cover; choose one classification", label, condition.Kind, condition.Interface.Type)
		}
		return nil, true, nil
	}

	if hasOps && projectFamily {
		return nil, false, fmt.Errorf("projection rule for %s (%s/%s) sets both operations and project/require/cover; choose one mechanism", label, condition.Kind, condition.Interface.Type)
	}

	if hasOps {
		caps, err := projectOperations(condition, rule, capabilities, index)
		return caps, false, err
	}
	if hasProject {
		caps, err := projectFields(condition, rule, capabilities, index)
		return caps, false, err
	}
	if projectFamily {
		return nil, false, fmt.Errorf("projection rule for %s (%s/%s) sets require/cover without project", label, condition.Kind, condition.Interface.Type)
	}
	return nil, false, fmt.Errorf("condition %s (%s/%s) matched a PADE-relevant rule with no operations or project clauses", label, condition.Kind, condition.Interface.Type)
}

func projectOperations(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest, index int) ([]string, error) {
	label := model.ConditionLabel(condition, index)
	if len(condition.Interface.Operations) == 0 {
		return nil, fmt.Errorf("condition %s (%s/%s) has no operations; operations-backed rules require interface.operations[].name", label, condition.Kind, condition.Interface.Type)
	}

	var emitted []string
	for _, operation := range condition.Interface.Operations {
		// Operations-backed projection requires a non-empty legacy name. Structured
		// method/path operations must not match a policy entry keyed by "".
		if operation.Name == "" {
			return nil, fmt.Errorf("condition %s (%s/%s) has an operation without a name; operations-backed rules require interface.operations[].name", label, condition.Kind, condition.Interface.Type)
		}
		mapping, ok := rule.Operations[operation.Name]
		if !ok {
			return nil, fmt.Errorf("no projection for %s (%s/%s) operation %q", label, condition.Kind, condition.Interface.Type, operation.Name)
		}
		if mapping.Capability == "" {
			return nil, fmt.Errorf("projection for %s (%s/%s) operation %q has an empty capability", label, condition.Kind, condition.Interface.Type, operation.Name)
		}
		if err := mergeCapability(capabilities, mapping.Capability, model.CapabilityRequest{
			Access:   mapping.Access,
			Required: !condition.Optional,
		}); err != nil {
			return nil, err
		}
		emitted = appendUnique(emitted, mapping.Capability)
	}
	return emitted, nil
}

func projectFields(condition model.Condition, rule model.ProjectionRule, capabilities map[string]model.CapabilityRequest, index int) ([]string, error) {
	label := model.ConditionLabel(condition, index)
	for _, pred := range rule.Require {
		ok, err := evaluatePredicate(condition, pred)
		if err != nil {
			return nil, fmt.Errorf("condition %s (%s/%s) require %s: %w", label, condition.Kind, condition.Interface.Type, pred.Path, err)
		}
		if !ok {
			return nil, fmt.Errorf("condition %s (%s/%s) does not satisfy require %s", label, condition.Kind, condition.Interface.Type, describePredicate(pred))
		}
	}

	emittedForCondition := 0
	var emitted []string
	covered := map[string]map[string]bool{} // path -> value -> covered by firing clause

	for _, clause := range rule.Project {
		if clause.Capability == "" {
			return nil, fmt.Errorf("projection rule for %s (%s/%s) has a project clause with an empty capability", label, condition.Kind, condition.Interface.Type)
		}
		satisfied := true
		for _, pred := range clause.When {
			ok, err := evaluatePredicate(condition, pred)
			if err != nil {
				return nil, fmt.Errorf("condition %s (%s/%s) project when %s: %w", label, condition.Kind, condition.Interface.Type, pred.Path, err)
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
			return nil, err
		}
		emittedForCondition++
		emitted = appendUnique(emitted, clause.Capability)

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
			return nil, fmt.Errorf("condition %s (%s/%s) cover %s: %w", label, condition.Kind, condition.Interface.Type, path, err)
		}
		if len(values) == 0 {
			return nil, fmt.Errorf("condition %s (%s/%s) cover %s: array is missing or empty", label, condition.Kind, condition.Interface.Type, path)
		}
		for _, value := range values {
			if !covered[path][value] {
				return nil, fmt.Errorf("condition %s (%s/%s) cover %s: value %q is not accounted for by any satisfied project clause", label, condition.Kind, condition.Interface.Type, path, value)
			}
		}
	}

	if emittedForCondition == 0 {
		return nil, fmt.Errorf("condition %s (%s/%s) matched a project rule but emitted no capabilities; use outsidePADE to accept with none", label, condition.Kind, condition.Interface.Type)
	}
	return emitted, nil
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

func findMatchingRule(rules []model.ProjectionRule, condition model.Condition, index int) (model.ProjectionRule, bool, error) {
	label := model.ConditionLabel(condition, index)
	var match *model.ProjectionRule
	for i := range rules {
		rule := &rules[i]
		if rule.Match.Kind != condition.Kind || rule.Match.InterfaceType != condition.Interface.Type {
			continue
		}
		if match != nil {
			return model.ProjectionRule{}, false, fmt.Errorf("multiple projection rules match %s (%s/%s)", label, condition.Kind, condition.Interface.Type)
		}
		match = rule
	}
	if match == nil {
		return model.ProjectionRule{}, false, nil
	}
	return *match, true, nil
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

func appendUnique(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}
