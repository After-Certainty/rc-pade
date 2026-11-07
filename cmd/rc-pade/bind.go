package main

import (
	"bytes"
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

type bindOptions struct {
	verifiedProfile string
	policy          string
	broker          string
	allowed         string
	output          string
	session         string
}

type brokerBinding struct {
	Provider string `json:"provider" yaml:"provider"`
	Broker   struct {
		Endpoint string `json:"endpoint" yaml:"endpoint"`
		Audience string `json:"audience" yaml:"audience"`
		Identity string `json:"identity" yaml:"identity"`
	} `json:"broker" yaml:"broker"`
}

type consumerBindings struct {
	Version      string                   `yaml:"version"`
	Capabilities map[string]brokerBinding `yaml:"capabilities"`
}

func runBindCommand(args []string) {
	fs := flag.NewFlagSet("bind", flag.ExitOnError)
	verifiedProfile := fs.String("verified-profile", "", "path to Profile bytes already accepted by the caller's Runtime Conditions trust/validation gate")
	policy := fs.String("policy", "", "path to an operator-owned rc-pade ProjectionPolicy YAML file")
	broker := fs.String("broker-binding", "", "path to operator-owned broker_binding JSON from the platform integration")
	allowed := fs.String("allow-capabilities", "", "operator-owned comma-separated capability allowlist")
	output := fs.String("output", "", "absolute PADE Consumer bindings path to replace atomically")
	session := fs.String("session-out", "", "optional absolute path for the generated PADE DevelopmentSession")
	_ = fs.Parse(args)

	if err := runBind(bindOptions{
		verifiedProfile: *verifiedProfile,
		policy:          *policy,
		broker:          *broker,
		allowed:         *allowed,
		output:          *output,
		session:         *session,
	}); err != nil {
		fatal(err)
	}
}

func runBind(c bindOptions) error {
	if c.output == "" || !filepath.IsAbs(c.output) {
		return errors.New("--output must be an absolute path")
	}
	if c.session != "" && !filepath.IsAbs(c.session) {
		return errors.New("--session-out must be an absolute path when provided")
	}

	// Revoke previous local capabilities before reading any caller-supplied
	// inputs. A failed trust handoff, projection, policy, or binding step must
	// never leave stale authority configured locally.
	if err := writeAtomic(c.output, []byte("version: \"0.1\"\ncapabilities: {}\n"), 0600); err != nil {
		return fmt.Errorf("revoke previous local bindings: %w", err)
	}

	if c.verifiedProfile == "" || c.policy == "" || c.broker == "" || c.allowed == "" {
		return errors.New("verified-profile, policy, broker-binding and allow-capabilities are required")
	}

	// Trust and Runtime Conditions validation intentionally happen before this
	// command. The --verified-profile name makes that boundary explicit:
	// rc-pade interprets already-accepted semantic demand; it does not know or
	// depend on the validator, signing format, or validation-report schema.
	var profile model.RuntimeConditionsProfile
	if err := readYAML(c.verifiedProfile, &profile); err != nil {
		return fmt.Errorf("verified Profile: %w", err)
	}

	var policy model.ProjectionPolicy
	if err := readYAML(c.policy, &policy); err != nil {
		return fmt.Errorf("operator projection policy: %w", err)
	}
	session, err := projector.Project(profile, policy, "")
	if err != nil {
		return fmt.Errorf("unsupported Runtime Conditions demand: %w", err)
	}

	allowed, err := parseAllowlist(c.allowed)
	if err != nil {
		return err
	}
	for capability := range session.Spec.Capabilities {
		if !allowed[capability] {
			return fmt.Errorf("projected capability %q is not approved by the operator allowlist", capability)
		}
	}

	binding, err := readBrokerBinding(c.broker)
	if err != nil {
		return err
	}

	out := consumerBindings{Version: "0.1", Capabilities: map[string]brokerBinding{}}
	for capability := range session.Spec.Capabilities {
		out.Capabilities[capability] = binding
	}

	// Produce portable intent before activating local bindings. Neither artifact
	// contains credential Material.
	if c.session != "" {
		sessionBytes, err := yaml.Marshal(session)
		if err != nil {
			return fmt.Errorf("marshal DevelopmentSession: %w", err)
		}
		if err := writeAtomic(c.session, sessionBytes, 0600); err != nil {
			return fmt.Errorf("write DevelopmentSession: %w", err)
		}
	}

	result, err := yaml.Marshal(out)
	if err != nil {
		return fmt.Errorf("marshal bindings: %w", err)
	}
	if err := writeAtomic(c.output, result, 0600); err != nil {
		return fmt.Errorf("write broker bindings: %w", err)
	}
	fmt.Printf("rc-pade: wrote %d broker-only capability bindings\n", len(out.Capabilities))
	return nil
}

func parseAllowlist(raw string) (map[string]bool, error) {
	allowed := make(map[string]bool)
	for _, capability := range strings.Split(raw, ",") {
		if capability == "" || strings.TrimSpace(capability) != capability || allowed[capability] {
			return nil, errors.New("operator capability allowlist has a blank, whitespace-padded or duplicate entry")
		}
		allowed[capability] = true
	}
	return allowed, nil
}

func readBrokerBinding(path string) (brokerBinding, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return brokerBinding{}, fmt.Errorf("read broker_binding: %w", err)
	}
	var binding brokerBinding
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&binding); err != nil {
		return brokerBinding{}, fmt.Errorf("parse broker_binding: %w", err)
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return brokerBinding{}, errors.New("broker_binding must be exactly one JSON object")
	}
	if binding.Provider != "broker" ||
		!strings.HasPrefix(binding.Broker.Endpoint, "https://") ||
		strings.TrimSpace(binding.Broker.Audience) == "" ||
		(binding.Broker.Identity != "gce" && binding.Broker.Identity != "cursor") {
		return brokerBinding{}, errors.New("broker_binding must be a complete broker-only configuration")
	}
	return binding, nil
}

func writeAtomic(path string, data []byte, mode os.FileMode) (err error) {
	dir := filepath.Dir(path)
	if err = os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, ".rc-pade-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if err = f.Chmod(mode); err != nil {
		return err
	}
	if _, err = f.Write(data); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}
