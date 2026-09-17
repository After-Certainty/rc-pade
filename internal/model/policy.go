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
// capability intent or explicitly outside PADE scope.
//
// outsidePADE: true means the condition is classified and intentionally emits
// no capability. That is distinct from an unmatched condition, which still
// fails closed. Do not treat a missing rule as "outside PADE".
//
// A PADE-relevant rule uses either legacy Operations (S3-style) or Project
// field clauses — not both. Project-mode rules may also set Require and Cover.
type ProjectionRule struct {
	Match       ConditionMatch              `yaml:"match"`
	OutsidePADE bool                        `yaml:"outsidePADE,omitempty"`
	Operations  map[string]OperationMapping `yaml:"operations,omitempty"`
	Require     []FieldPredicate            `yaml:"require,omitempty"`
	Project     []ProjectClause             `yaml:"project,omitempty"`
	Cover       []string                    `yaml:"cover,omitempty"`
}

type ConditionMatch struct {
	Kind          string `yaml:"kind"`
	InterfaceType string `yaml:"interfaceType"`
}

type OperationMapping struct {
	Capability string `yaml:"capability"`
	Access     string `yaml:"access,omitempty"`
}

// FieldPredicate is a single equals or contains check on an interface field path.
// Exactly one of Equals or Contains should be set.
type FieldPredicate struct {
	Path     string `yaml:"path"`
	Equals   string `yaml:"equals,omitempty"`
	Contains string `yaml:"contains,omitempty"`
}

// ProjectClause emits one PADE capability when all When predicates hold (AND).
type ProjectClause struct {
	When       []FieldPredicate `yaml:"when,omitempty"`
	Capability string           `yaml:"capability"`
	Access     string           `yaml:"access,omitempty"`
}
