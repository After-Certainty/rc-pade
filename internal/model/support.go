package model

// Support report types are a local rc-pade platform-support representation.
// They are not an upstream Runtime Conditions standard and must not be treated
// as RC validation evidence, authorization decisions, or provider fulfillment.

const (
	SupportAPIVersion = "rc-pade.local/v1alpha1"
	SupportKind       = "PlatformSupportReport"
)

// SupportOutcome classifies one Condition at the platform-support boundary.
type SupportOutcome string

const (
	// SupportSupportedProjected: matched a PADE-relevant rule and projected
	// one or more capabilities.
	SupportSupportedProjected SupportOutcome = "supported_projected"
	// SupportUnsupportedRequired: no matching rule for a required Condition
	// (fail closed).
	SupportUnsupportedRequired SupportOutcome = "unsupported_required"
	// SupportUnsupportedOptional: no matching rule for an optional Condition.
	// Continuation requires operator onUnsupportedOptional: continue.
	SupportUnsupportedOptional SupportOutcome = "unsupported_optional"
	// SupportOutsidePADE: matched an explicit outsidePADE classification.
	SupportOutsidePADE SupportOutcome = "outside_pade"
	// SupportProjectionError: matched a rule but projection policy failed
	// (require/cover/conflict/misconfiguration). Distinct from unmatched
	// unsupported demand and from broker authorization failures.
	SupportProjectionError SupportOutcome = "projection_policy_error"
)

// PlatformSupportReport records local platform-support outcomes for one
// Project invocation. It does not represent Runtime Conditions validity,
// signature trust, broker authorization, or provider fulfillment.
//
// When Complete is false, Conditions may be a prefix of the Profile (evaluation
// stopped at the first failing Condition). Treat incomplete reports as
// diagnostics only, not a full platform-support evaluation.
type PlatformSupportReport struct {
	APIVersion string `yaml:"apiVersion"`
	Kind       string `yaml:"kind"`
	Profile    string `yaml:"profile,omitempty"`
	// Complete is true only when every Condition was evaluated and projection
	// returned successfully. False means a partial diagnostic.
	Complete   bool                     `yaml:"complete"`
	Conditions []ConditionSupportResult `yaml:"conditions"`
	// ContinuedDespiteUnsupportedOptional is true when at least one optional
	// unmatched Condition was skipped under onUnsupportedOptional: continue.
	ContinuedDespiteUnsupportedOptional bool `yaml:"continuedDespiteUnsupportedOptional,omitempty"`
}

// ConditionSupportResult is one Condition's platform-support outcome.
type ConditionSupportResult struct {
	Index         int            `yaml:"index"`
	Label         string         `yaml:"label"`
	Name          string         `yaml:"name,omitempty"`
	Kind          string         `yaml:"kind"`
	InterfaceType string         `yaml:"interfaceType"`
	Optional      bool           `yaml:"optional"`
	Outcome       SupportOutcome `yaml:"outcome"`
	Detail        string         `yaml:"detail,omitempty"`
	Capabilities  []string       `yaml:"capabilities,omitempty"`
}
