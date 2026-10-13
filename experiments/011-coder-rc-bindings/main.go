// Experiment 011 trusted pipeline adapter: RC validation -> rc-pade projection
// -> a PADE Consumer broker-only bindings file for a Coder workspace.
// No credential is materialized here. This is NOT an RC validator or a grant.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/After-Certainty/rc-pade/internal/model"
	"github.com/After-Certainty/rc-pade/internal/projector"
	"gopkg.in/yaml.v3"
)

type options struct {
	profile, report, policy, broker, allowed, output, session string
}

type validationReport struct {
	Accepted bool `yaml:"accepted"`
	Validator struct {
		Module  string `yaml:"module"`
		Version string `yaml:"version"`
	} `yaml:"validator"`
	Profile struct {
		SHA256 string `yaml:"sha256"`
		Bytes  int    `yaml:"bytes"`
	} `yaml:"profile"`
	Conditions []struct {
		Index         int    `yaml:"index"`
		Kind          string `yaml:"kind"`
		InterfaceType string `yaml:"interfaceType"`
		Valid         bool   `yaml:"valid"`
	} `yaml:"conditions"`
}

type brokerBinding struct {
	Provider string `json:"provider" yaml:"provider"`
	Broker struct {
		Endpoint string `json:"endpoint" yaml:"endpoint"`
		Audience string `json:"audience" yaml:"audience"`
		Identity string `json:"identity" yaml:"identity"`
	} `json:"broker" yaml:"broker"`
}

type bindings struct {
	Version      string                   `yaml:"version"`
	Capabilities map[string]brokerBinding `yaml:"capabilities"`
}

func main() {
	var c options
	flag.StringVar(&c.profile, "profile", "", "exact Profile validated by trusted pipeline")
	flag.StringVar(&c.report, "validation-report", "", "report from trusted rcvalidate invocation")
	flag.StringVar(&c.policy, "policy", "", "operator-owned rc-pade projection policy")
	flag.StringVar(&c.broker, "broker-binding", "", "operator-owned broker_binding JSON output from pade-coder")
	flag.StringVar(&c.allowed, "allow-capabilities", "", "operator-owned comma-separated capability allowlist")
	flag.StringVar(&c.output, "output", "", "module.pade.bindings_path (expanded to an absolute path)")
	flag.StringVar(&c.session, "session-out", "", "optional generated PADE DevelopmentSession path")
	flag.Parse()
	if err := run(c); err != nil {
		fmt.Fprintln(os.Stderr, "experiment-011:", err)
		os.Exit(1)
	}
}

func run(c options) error {
	if c.output == "" || !filepath.IsAbs(c.output) {
		return errors.New("--output must be an absolute path")
	}
	// Fail closed on *every* invocation, including invalid/missing input or
	// failed projection. Do not carry over a prior workspace's capabilities.
	if err := writeAtomic(c.output, []byte("version: \"0.1\"\ncapabilities: {}\n"), 0600); err != nil {
		return fmt.Errorf("revoke previous local bindings: %w", err)
	}
	if c.profile == "" || c.report == "" || c.policy == "" || c.broker == "" || c.allowed == "" {
		return errors.New("profile, validation-report, policy, broker-binding and allow-capabilities are required")
	}
	profileBytes, err := os.ReadFile(c.profile)
	if err != nil { return fmt.Errorf("read Profile: %w", err) }
	var profile model.RuntimeConditionsProfile
	if err := yaml.Unmarshal(profileBytes, &profile); err != nil { return fmt.Errorf("parse Profile: %w", err) }

	var evidence validationReport
	if err := loadYAML(c.report, &evidence, true); err != nil { return fmt.Errorf("validation evidence: %w", err) }
	sum := sha256.Sum256(profileBytes)
	if !evidence.Accepted ||
		evidence.Validator.Module != "github.com/runtimeconditions/rc-extension-resolver" ||
		evidence.Validator.Version == "" ||
		evidence.Profile.SHA256 != hex.EncodeToString(sum[:]) ||
		evidence.Profile.Bytes != len(profileBytes) ||
		len(evidence.Conditions) == 0 ||
		len(evidence.Conditions) != len(profile.Conditions) {
		return errors.New("missing, rejected, incomplete, or mismatched validation evidence")
	}
	seen := make(map[int]bool)
	for _, e := range evidence.Conditions {
		if e.Index < 0 || e.Index >= len(profile.Conditions) || seen[e.Index] || !e.Valid ||
			e.Kind != profile.Conditions[e.Index].Kind ||
			e.InterfaceType != profile.Conditions[e.Index].Interface.Type {
			return errors.New("validation evidence does not cover each Profile condition")
		}
		seen[e.Index] = true
	}

	var policy model.ProjectionPolicy
	if err := loadYAML(c.policy, &policy, true); err != nil { return fmt.Errorf("operator projection policy: %w", err) }
	session, err := projector.Project(profile, policy, "")
	if err != nil { return fmt.Errorf("unsupported Runtime Conditions demand: %w", err) }

	allowed := make(map[string]bool)
	for _, capability := range strings.Split(c.allowed, ",") {
		if capability == "" || strings.TrimSpace(capability) != capability || allowed[capability] {
			return errors.New("operator capability allowlist has a blank, whitespace-padded or duplicate entry")
		}
		allowed[capability] = true
	}
	for capability := range session.Spec.Capabilities {
		if !allowed[capability] {
			return fmt.Errorf("projected capability %q is not approved by the operator allowlist", capability)
		}
	}
	rawBroker, err := os.ReadFile(c.broker)
	if err != nil { return fmt.Errorf("read broker_binding: %w", err) }
	var binding brokerBinding
	dec := json.NewDecoder(bytes.NewReader(rawBroker))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&binding); err != nil { return fmt.Errorf("parse broker_binding: %w", err) }
	if err := dec.Decode(new(any)); err != io.EOF { return errors.New("broker_binding must be exactly one JSON object") }
	if binding.Provider != "broker" || !strings.HasPrefix(binding.Broker.Endpoint, "https://") ||
		strings.TrimSpace(binding.Broker.Audience) == "" ||
		(binding.Broker.Identity != "gce" && binding.Broker.Identity != "cursor") {
		return errors.New("broker_binding must be a complete broker-only configuration")
	}

	out := bindings{Version: "0.1", Capabilities: map[string]brokerBinding{}}
	for capability := range session.Spec.Capabilities {
		out.Capabilities[capability] = binding
	}

	// Produce the portable session before activating the bindings. No
	// credential values are placed in either artifact.
	if c.session != "" {
		sessionBytes, err := yaml.Marshal(session)
		if err != nil { return err }
		if err := writeAtomic(c.session, sessionBytes, 0600); err != nil { return fmt.Errorf("write DevelopmentSession: %w", err) }
	}
	result, err := yaml.Marshal(out)
	if err != nil { return err }
	if err := writeAtomic(c.output, result, 0600); err != nil { return fmt.Errorf("write broker bindings: %w", err) }
	fmt.Printf("experiment-011: wrote %d broker-only capability bindings\n", len(out.Capabilities))
	return nil
}

func loadYAML(path string, v any, knownFields bool) error {
	data, err := os.ReadFile(path)
	if err != nil { return err }
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	decoder.KnownFields(knownFields)
	if err := decoder.Decode(v); err != nil { return err }
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("expected exactly one YAML document")
	}
	return nil
}

func writeAtomic(path string, data []byte, mode os.FileMode) (err error) {
	dir := filepath.Dir(path)
	if err = os.MkdirAll(dir, 0700); err != nil { return err }
	var f *os.File
	f, err = os.CreateTemp(dir, ".rc-pade-bindings-*")
	if err != nil { return err }
	defer os.Remove(f.Name())
	defer f.Close()
	if err = f.Chmod(mode); err != nil { return err }
	if _, err = f.Write(data); err != nil { return err }
	if err = f.Sync(); err != nil { return err }
	if err = f.Close(); err != nil { return err }
	return os.Rename(f.Name(), path)
}
