// Command rcvalidate is the Experiment 009 validation gate. It is a thin,
// experiment-local wrapper around the upstream Runtime Conditions resolver
// (github.com/runtimeconditions/rc-extension-resolver). It is not imported by
// rc-pade and does not rewrite the Profile it validates.
//
// Scope is whatever the pinned resolver implements: extension resolution
// (dependencies, metadata.id, cycles), merge conflicts, per-Condition kind /
// interface.type lookup, and the extension JSON Schemas bound to each
// Condition's (kind, interfaceType). It is not a full sixth-draft validator.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"sort"

	resolver "github.com/runtimeconditions/rc-extension-resolver"
	"gopkg.in/yaml.v3"
)

const resolverModule = "github.com/runtimeconditions/rc-extension-resolver"

// Extension identifier URIs are not currently served over HTTP, so they are
// mapped onto files in a pinned runtimeconditions/extensions checkout. This is
// transport only; resolution and validation stay in the upstream resolver.
var extensionPaths = map[string]string{
	"https://runtimeconditions.io/extensions/common-integrations/v1alpha1/runtimeconditions.extension.yaml": "catalog/rc/common-integrations/common-integrations-v1alpha1.yaml",
	"https://runtimeconditions.io/extensions/env-configuration/v1alpha1/runtimeconditions.extension.yaml":   "catalog/rc/env-configuration/env-configuration-v1alpha1.yaml",
	"https://runtimeconditions.io/extensions/google-analytics/0.1.0/runtimeconditions.extension.yaml":       "catalog/google/analytics/releases/0.1.0/runtimeconditions.extension.yaml",
	"https://runtimeconditions.io/extensions/source-control/0.1.0/runtimeconditions.extension.yaml":         "catalog/rc/source-control/releases/0.1.0/runtimeconditions.extension.yaml",
}

type report struct {
	Validator          validatorInfo     `yaml:"validator"`
	Profile            profileInfo       `yaml:"profile"`
	ResolvedExtensions []string          `yaml:"resolvedExtensions"`
	Conditions         []conditionReport `yaml:"conditions"`
	Accepted           bool              `yaml:"accepted"`
	Error              string            `yaml:"error,omitempty"`
}

type validatorInfo struct {
	Module  string `yaml:"module"`
	Version string `yaml:"version"`
	Scope   string `yaml:"scope"`
}

type profileInfo struct {
	Path     string   `yaml:"path"`
	SHA256   string   `yaml:"sha256"`
	Bytes    int      `yaml:"bytes"`
	Declared []string `yaml:"declaredExtensions"`
}

type conditionReport struct {
	Index         int      `yaml:"index"`
	Name          string   `yaml:"name,omitempty"`
	Kind          string   `yaml:"kind"`
	InterfaceType string   `yaml:"interfaceType"`
	Valid         bool     `yaml:"valid"`
	Errors        []string `yaml:"errors,omitempty"`
}

func main() {
	profilePath := flag.String("profile", "", "RuntimeConditionsProfile YAML to validate")
	extensionsRoot := flag.String("extensions-root", "", "runtimeconditions/extensions checkout")
	reportPath := flag.String("report", "", "where to write the validation report YAML")
	flag.Parse()
	if *profilePath == "" || *extensionsRoot == "" || *reportPath == "" {
		flag.Usage()
		os.Exit(2)
	}

	r, code := run(*profilePath, *extensionsRoot)
	out, err := yaml.Marshal(r)
	if err != nil {
		fmt.Fprintln(os.Stderr, "rcvalidate: marshal report:", err)
		os.Exit(2)
	}
	if err := os.WriteFile(*reportPath, out, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "rcvalidate: write report:", err)
		os.Exit(2)
	}
	if r.Error != "" {
		fmt.Fprintln(os.Stderr, "rcvalidate:", r.Error)
	}
	for _, c := range r.Conditions {
		for _, e := range c.Errors {
			fmt.Fprintf(os.Stderr, "rcvalidate: conditions[%d] %s (%s/%s): %s\n", c.Index, c.Name, c.Kind, c.InterfaceType, e)
		}
	}
	fmt.Printf("accepted=%t sha256=%s\n", r.Accepted, r.Profile.SHA256)
	os.Exit(code)
}

// run returns exit code 0 when every Condition is accepted, 1 when the Profile
// is rejected, and 2 when validation could not be performed.
func run(profilePath, extensionsRoot string) (report, int) {
	r := report{Validator: validatorInfo{
		Module:  resolverModule,
		Version: resolverVersion(),
		Scope:   "rc-extension-resolver current implementation: extension resolution, merge conflicts, kind/interface.type lookup, and (kind, interfaceType)-bound extension JSON Schemas; not a full sixth-draft conformance check",
	}}

	data, err := os.ReadFile(profilePath)
	if err != nil {
		r.Error = err.Error()
		return r, 2
	}
	sum := sha256.Sum256(data)
	r.Profile = profileInfo{Path: profilePath, SHA256: hex.EncodeToString(sum[:]), Bytes: len(data)}

	var profile struct {
		Extensions []string         `yaml:"extensions"`
		Conditions []map[string]any `yaml:"conditions"`
	}
	if err := yaml.Unmarshal(data, &profile); err != nil {
		r.Error = fmt.Sprintf("parse profile: %v", err)
		return r, 1
	}
	r.Profile.Declared = profile.Extensions

	loader, err := fileLoader(extensionsRoot)
	if err != nil {
		r.Error = err.Error()
		return r, 2
	}
	graph, err := resolveAll(loader, profile.Extensions)
	if err != nil {
		r.Error = fmt.Sprintf("resolving extensions: %v", err)
		// An extension this harness cannot fetch is a transport gap, not an
		// RC rejection of the Profile; still fail closed.
		var fetchErr *resolver.FetchError
		if errors.As(err, &fetchErr) {
			return r, 2
		}
		return r, 1
	}
	for _, ext := range graph.Extensions {
		r.ResolvedExtensions = append(r.ResolvedExtensions, ext.Metadata.ID)
	}
	catalog, err := resolver.Merge(graph)
	if err != nil {
		r.Error = fmt.Sprintf("merging extensions: %v", err)
		return r, 1
	}

	accepted := true
	for i, condition := range profile.Conditions {
		c := conditionReport{Index: i}
		c.Name, _ = condition["name"].(string)
		c.Kind, _ = condition["kind"].(string)
		if iface, ok := condition["interface"].(map[string]any); ok {
			c.InterfaceType, _ = iface["type"].(string)
		}
		result, err := catalog.ValidateCondition(condition)
		switch {
		case err != nil:
			c.Errors = []string{err.Error()}
		case !result.Valid:
			c.Errors = append([]string(nil), result.Errors...)
			sort.Strings(c.Errors)
		default:
			c.Valid = true
		}
		accepted = accepted && c.Valid
		r.Conditions = append(r.Conditions, c)
	}
	r.Accepted = accepted
	if !accepted {
		return r, 1
	}
	return r, 0
}

// resolveAll is copied from runtimeconditions/rc-admission-webhook@91e97af
// (internal/webhook/v1alpha1/runtimeconditionsprofile_webhook.go). The
// resolver library resolves one root at a time; a Profile declares several.
func resolveAll(loader resolver.LoaderFunc, extensionURIs []string) (*resolver.ResolvedGraph, error) {
	r := resolver.NewResolver(loader)
	byID := make(map[string]*resolver.ExtensionDefinition)
	var order []*resolver.ExtensionDefinition

	for _, root := range extensionURIs {
		graph, err := r.Resolve(root)
		if err != nil {
			return nil, err
		}
		for _, ext := range graph.Extensions {
			if _, ok := byID[ext.Metadata.ID]; ok {
				continue
			}
			byID[ext.Metadata.ID] = ext
			order = append(order, ext)
		}
	}

	return &resolver.ResolvedGraph{Extensions: order, ByID: byID}, nil
}

func fileLoader(root string) (resolver.LoaderFunc, error) {
	docs := make(map[string][]byte, len(extensionPaths))
	for uri, rel := range extensionPaths {
		data, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			return nil, fmt.Errorf("load extension %s: %w", uri, err)
		}
		docs[uri] = data
	}
	return resolver.NewInMemoryLoader(docs), nil
}

func resolverVersion() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	for _, dep := range info.Deps {
		if dep.Path == resolverModule {
			if dep.Replace != nil {
				return dep.Version + " => " + dep.Replace.Path + " " + dep.Replace.Version
			}
			return dep.Version
		}
	}
	return "unknown"
}
