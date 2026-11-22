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
	Extensions []string    `yaml:"extensions,omitempty"`
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
	Name          string         `yaml:"name,omitempty"`
	Optional      bool           `yaml:"optional,omitempty"`
	Kind          string         `yaml:"kind"`
	Interface     RCInterface    `yaml:"interface"`
	Configuration map[string]any `yaml:"configuration,omitempty"`
}

// RCInterface keeps typed core fields for the legacy operations projection path
// and preserves arbitrary extension-defined interface keys in Fields.
//
// After UnmarshalYAML, Fields is authoritative for the full interface mapping
// (including the operations array as decoded from YAML). Typed Type/Operations
// are derived convenience views for projection. MarshalYAML remits Fields when
// present; do not assume typed Operations are re-serialized independently.
type RCInterface struct {
	Type       string
	Operations []Operation
	// Fields holds the full interface mapping after decode (type, operations,
	// provider, access, and any other extension-defined keys).
	Fields map[string]any
}

// Operation keeps the legacy name-based projection key and preserves
// extension-defined operation fields (method, path, schemas, …) in Fields.
//
// After UnmarshalYAML, Fields is authoritative for the operation mapping.
// Name is a derived convenience for operations-backed projection rules and is
// empty when the upstream operation uses structured keys (e.g. method/path)
// without a legacy name. MarshalYAML remits Fields when present.
type Operation struct {
	Name   string
	Fields map[string]any
}

// ConditionLabel returns a local reporting label for logs and errors.
// When the Condition has a name, that name is used. Otherwise the label is
// index-based (condition[i]). This does not invent or write a name into the
// Profile; it is reporting-only.
func ConditionLabel(condition Condition, index int) string {
	if condition.Name != "" {
		return condition.Name
	}
	return fmt.Sprintf("condition[%d]", index)
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

func (o *Operation) UnmarshalYAML(value *yaml.Node) error {
	if value == nil || value.Kind == yaml.ScalarNode && value.Tag == "!!null" {
		*o = Operation{}
		return nil
	}
	if value.Kind != yaml.MappingNode {
		return fmt.Errorf("operation must be a mapping")
	}

	var fields map[string]any
	if err := value.Decode(&fields); err != nil {
		return fmt.Errorf("decode operation: %w", err)
	}
	if fields == nil {
		fields = map[string]any{}
	}

	name := ""
	if nameRaw, ok := fields["name"]; ok && nameRaw != nil {
		nameStr, ok := nameRaw.(string)
		if !ok {
			return fmt.Errorf("operation.name must be a string")
		}
		name = nameStr
	}

	o.Name = name
	o.Fields = fields
	return nil
}

func (o Operation) MarshalYAML() (any, error) {
	if o.Fields != nil {
		return o.Fields, nil
	}
	if o.Name == "" {
		return map[string]any{}, nil
	}
	return map[string]any{"name": o.Name}, nil
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
