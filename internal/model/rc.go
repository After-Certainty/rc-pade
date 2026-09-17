package model

import (
	"fmt"

	"gopkg.in/yaml.v3"
)

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

// RCInterface keeps typed core fields for the legacy operations projection path
// and preserves arbitrary extension-defined interface keys in Fields.
type RCInterface struct {
	Type       string
	Operations []Operation
	// Fields holds the full interface mapping after decode (type, operations,
	// provider, access, and any other extension-defined keys).
	Fields map[string]any
}

type Operation struct {
	Name string `yaml:"name"`
}

func (i *RCInterface) UnmarshalYAML(value *yaml.Node) error {
	if value == nil || value.Kind == yaml.ScalarNode && value.Tag == "!!null" {
		*i = RCInterface{}
		return nil
	}
	if value.Kind != yaml.MappingNode {
		return fmt.Errorf("interface must be a mapping")
	}

	var fields map[string]any
	if err := value.Decode(&fields); err != nil {
		return fmt.Errorf("decode interface: %w", err)
	}
	if fields == nil {
		fields = map[string]any{}
	}

	typeRaw, ok := fields["type"]
	if !ok {
		return fmt.Errorf("interface.type is required")
	}
	typeStr, ok := typeRaw.(string)
	if !ok {
		return fmt.Errorf("interface.type must be a string")
	}

	var operations []Operation
	if opsRaw, exists := fields["operations"]; exists && opsRaw != nil {
		opsNode, err := encodeToNode(opsRaw)
		if err != nil {
			return fmt.Errorf("interface.operations: %w", err)
		}
		if err := opsNode.Decode(&operations); err != nil {
			return fmt.Errorf("interface.operations: %w", err)
		}
	}

	i.Type = typeStr
	i.Operations = operations
	i.Fields = fields
	return nil
}

func (i RCInterface) MarshalYAML() (any, error) {
	if i.Fields != nil {
		return i.Fields, nil
	}
	out := map[string]any{}
	if i.Type != "" {
		out["type"] = i.Type
	}
	if len(i.Operations) > 0 {
		out["operations"] = i.Operations
	}
	return out, nil
}

func encodeToNode(v any) (*yaml.Node, error) {
	var node yaml.Node
	data, err := yaml.Marshal(v)
	if err != nil {
		return nil, err
	}
	if err := yaml.Unmarshal(data, &node); err != nil {
		return nil, err
	}
	// Unmarshal into Node wraps document; use content[0] when present.
	if node.Kind == yaml.DocumentNode && len(node.Content) == 1 {
		return node.Content[0], nil
	}
	return &node, nil
}
