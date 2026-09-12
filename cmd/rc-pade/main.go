package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/After-Certainty/rc-pade/internal/model"
	"github.com/After-Certainty/rc-pade/internal/projector"
	"gopkg.in/yaml.v3"
)

func main() {
	if len(os.Args) < 2 || os.Args[1] != "generate" {
		usage()
		os.Exit(2)
	}

	fs := flag.NewFlagSet("generate", flag.ExitOnError)
	profilePath := fs.String("profile", "", "path to a RuntimeConditionsProfile YAML file")
	policyPath := fs.String("policy", "", "path to an rc-pade ProjectionPolicy YAML file")
	name := fs.String("name", "", "override PADE metadata.name")
	_ = fs.Parse(os.Args[2:])

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
	if err := yaml.Unmarshal(data, into); err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}
	return nil
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "rc-pade:", err)
	os.Exit(1)
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: rc-pade generate --profile runtime-conditions.yaml --policy policy.yaml [--name session-name]")
}
