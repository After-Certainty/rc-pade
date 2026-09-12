package model

const (
	PADEAPIVersion = "pade.local/v1alpha1"
	PADEKind       = "DevelopmentSession"
)

type DevelopmentSession struct {
	APIVersion string       `yaml:"apiVersion"`
	Kind       string       `yaml:"kind"`
	Metadata   PADEMetadata `yaml:"metadata"`
	Spec       PADESpec     `yaml:"spec"`
}

type PADEMetadata struct {
	Name        string            `yaml:"name"`
	Annotations map[string]string `yaml:"annotations,omitempty"`
}

type PADESpec struct {
	Capabilities map[string]CapabilityRequest `yaml:"capabilities,omitempty"`
}

type CapabilityRequest struct {
	Access   string `yaml:"access,omitempty"`
	Required bool   `yaml:"required"`
}
