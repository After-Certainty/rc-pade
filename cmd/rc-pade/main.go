package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/After-Certainty/rc-pade/internal/model"
	"github.com/After-Certainty/rc-pade/internal/projector"
	"gopkg.in/yaml.v3"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "generate":
		runGenerate(os.Args[2:])
	case "bind":
		runBindCommand(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
}

func runGenerate(args []string) {
	out, err := generate(args)
	if err != nil {
		fatal(err)
	}
	_, _ = os.Stdout.Write(out)
}

type generateOptions struct {
	profile       string
	policy        string
	name          string
	supportReport string
}

func generate(args []string) ([]byte, error) {
	fs := flag.NewFlagSet("generate", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	profilePath := fs.String("profile", "", "path to a RuntimeConditionsProfile YAML file")
	policyPath := fs.String("policy", "", "path to an rc-pade ProjectionPolicy YAML file")
	name := fs.String("name", "", "override PADE metadata.name")
	supportReport := fs.String("support-report", "", "path for a local PlatformSupportReport YAML (required when onUnsupportedOptional: continue)")
	if err := fs.Parse(args); err != nil {
		return nil, err
	}
	if *profilePath == "" || *policyPath == "" {
		return nil, errors.New("generate requires --profile and --policy")
	}
	return runGenerateOpts(generateOptions{
		profile:       *profilePath,
		policy:        *policyPath,
		name:          *name,
		supportReport: *supportReport,
	})
}

func runGenerateOpts(c generateOptions) ([]byte, error) {
	if err := rejectPathConflicts(map[string]string{
		"--profile":        c.profile,
		"--policy":         c.policy,
		"--support-report": c.supportReport,
	}); err != nil {
		return nil, err
	}

	var profile model.RuntimeConditionsProfile
	if err := readYAML(c.profile, &profile); err != nil {
		return nil, err
	}
	var policy model.ProjectionPolicy
	if err := readYAML(c.policy, &policy); err != nil {
		return nil, err
	}
	if err := requireSupportReportForContinue(policy, c.supportReport); err != nil {
		return nil, err
	}

	session, report, err := projector.ProjectWithSupport(profile, policy, c.name)
	if c.supportReport != "" {
		if writeErr := writeSupportReport(c.supportReport, report); writeErr != nil {
			return nil, writeErr
		}
	}
	if err != nil {
		return nil, err
	}
	emitContinueDiagnostics(report)

	out, err := yaml.Marshal(session)
	if err != nil {
		return nil, fmt.Errorf("marshal DevelopmentSession: %w", err)
	}
	return out, nil
}

func requireSupportReportForContinue(policy model.ProjectionPolicy, supportReport string) error {
	if policy.OnUnsupportedOptional == model.UnsupportedOptionalContinue && supportReport == "" {
		return errors.New("onUnsupportedOptional: continue requires --support-report so unsupported optional outcomes are explicit")
	}
	return nil
}

func emitContinueDiagnostics(report model.PlatformSupportReport) {
	if !report.ContinuedDespiteUnsupportedOptional {
		return
	}
	for _, cond := range report.Conditions {
		if cond.Outcome != model.SupportUnsupportedOptional {
			continue
		}
		fmt.Fprintf(os.Stderr, "rc-pade: unsupported optional %s (%s/%s) skipped under onUnsupportedOptional: continue\n", cond.Label, cond.Kind, cond.InterfaceType)
	}
}

func writeSupportReport(path string, report model.PlatformSupportReport) error {
	out, err := yaml.Marshal(report)
	if err != nil {
		return fmt.Errorf("marshal PlatformSupportReport: %w", err)
	}
	if err := writeAtomic(path, out, 0600); err != nil {
		return fmt.Errorf("write PlatformSupportReport: %w", err)
	}
	return nil
}

func readYAML(path string, into any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	// Operator policy has a closed vocabulary: a misspelled guard must not
	// silently disappear. Profiles retain extension-defined fields and use
	// upstream Runtime Conditions validation, not this policy schema.
	_, policy := into.(*model.ProjectionPolicy)
	dec.KnownFields(policy)
	if err := dec.Decode(into); err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return fmt.Errorf("parse %s: expected exactly one YAML document", path)
	}
	return nil
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "rc-pade:", err)
	os.Exit(1)
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage:")
	fmt.Fprintln(os.Stderr, "  rc-pade generate --profile runtime-conditions.yaml --policy policy.yaml [--name session-name] [--support-report report.yaml]")
	fmt.Fprintln(os.Stderr, "  rc-pade bind --verified-profile verified-profile.yaml --policy policy.yaml --broker-binding broker.json --allow-capabilities cap.one,cap.two --output /absolute/bindings.yaml [--session-out /absolute/session.yaml] [--support-report report.yaml]")
}
