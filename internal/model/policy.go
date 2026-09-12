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

type ProjectionRule struct {
	Match      ConditionMatch              `yaml:"match"`
	Operations map[string]OperationMapping `yaml:"operations"`
}

type ConditionMatch struct {
	Kind          string `yaml:"kind"`
	InterfaceType string `yaml:"interfaceType"`
}

type OperationMapping struct {
	Capability string `yaml:"capability"`
	Access     string `yaml:"access,omitempty"`
}
