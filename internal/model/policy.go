package model

const (
	ProjectionPolicyAPIVersion = "rc-pade.local/v1alpha1"
	ProjectionPolicyKind       = "ProjectionPolicy"
)

type ProjectionPolicy struct {
	APIVersion string           `yaml:"apiVersion"`
	Kind       string           `yaml:"kind"`
	Rules      []ProjectionRule `yaml:"rules"`
}

// ProjectionRule maps a matched Runtime Conditions condition either into PADE
// capability intent (via Operations) or explicitly outside PADE scope.
//
// outsidePADE: true means the condition is classified and intentionally emits
// no capability. That is distinct from an unmatched condition, which still
// fails closed. Do not treat a missing rule as "outside PADE".
type ProjectionRule struct {
	Match       ConditionMatch              `yaml:"match"`
	OutsidePADE bool                        `yaml:"outsidePADE,omitempty"`
	Operations  map[string]OperationMapping `yaml:"operations,omitempty"`
}

type ConditionMatch struct {
	Kind          string `yaml:"kind"`
	InterfaceType string `yaml:"interfaceType"`
}

type OperationMapping struct {
	Capability string `yaml:"capability"`
	Access     string `yaml:"access,omitempty"`
}
