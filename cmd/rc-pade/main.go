package main

import (
	"bytes"
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
	fs := flag.NewFlagSet("generate", flag.ExitOnError)
	profilePath := fs.String("profile", "", "path to a RuntimeConditionsProfile YAML file")
	policyPath := fs.String("policy", "", "path to an rc-pade ProjectionPolicy YAML file")
	name := fs.String("name", "", "override PADE metadata.name")
	_ = fs.Parse(args)

	if *profilePath == "" || *policyPath == "" {
		fs.Usage()
		os.Exit(2)
	}

	var profile model.RuntimeConditionsProfile
	if err := readYAML(*profilePath, &profile); err != nil {
		fatal(err)
	}
	var policy model.ProjectionPolicy
	if err := readYAML(*policyPath, &policy); err != nil {
		fatal(err)
	}

	session, err := projector.Project(profile, policy, *name)
	if err != nil {
		fatal(err)
	}

	out, err := yaml.Marshal(session)
	if err != nil {
		fatal(fmt.Errorf("marshal DevelopmentSession: %w", err))
	}
	_, _ = os.Stdout.Write(out)
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
	fmt.Fprintln(os.Stderr, "  rc-pade generate --profile runtime-conditions.yaml --policy policy.yaml [--name session-name]")
	fmt.Fprintln(os.Stderr, "  rc-pade bind --verified-profile verified-profile.yaml --policy policy.yaml --broker-binding broker.json --allow-capabilities cap.one,cap.two --output /absolute/bindings.yaml [--session-out /absolute/session.yaml]")
}
