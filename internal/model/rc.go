package model

const (
	RuntimeConditionsAPIVersion = "runtimeconditions.io/v1alpha1"
	RuntimeConditionsKind       = "RuntimeConditionsProfile"
)

type RuntimeConditionsProfile struct {
	APIVersion string      `yaml:"apiVersion"`
	Kind       string      `yaml:"kind"`
	Metadata   RCMetadata  `yaml:"metadata"`
	Workload   Workload    `yaml:"workload"`
	Conditions []Condition `yaml:"conditions"`
}

type RCMetadata struct {
	Name string `yaml:"name"`
}

type Workload struct {
	URI     string `yaml:"uri,omitempty"`
	Version string `yaml:"version,omitempty"`
}

type Condition struct {
	Name      string      `yaml:"name,omitempty"`
	Optional  bool        `yaml:"optional,omitempty"`
	Kind      string      `yaml:"kind"`
	Interface RCInterface `yaml:"interface"`
}

type RCInterface struct {
	Type       string      `yaml:"type"`
	Operations []Operation `yaml:"operations,omitempty"`
}

type Operation struct {
	Name string `yaml:"name"`
}
