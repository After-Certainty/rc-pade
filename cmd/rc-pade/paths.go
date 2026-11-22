package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

// canonicalPath returns a cleaned absolute path with intermediate symlinks
// resolved. When the final path component does not exist yet (common for
// outputs), the parent directory is resolved and the base name is rejoined.
func canonicalPath(path string) (string, error) {
	if path == "" {
		return "", nil
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	abs = filepath.Clean(abs)
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved, nil
	}
	dir, base := filepath.Dir(abs), filepath.Base(abs)
	resolvedDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		// Parent may also be missing; keep the absolute cleaned path so textual
		// collisions still compare consistently.
		if !os.IsNotExist(err) {
			return "", err
		}
		return abs, nil
	}
	return filepath.Join(resolvedDir, base), nil
}

// samePath reports whether two filesystem paths refer to the same location
// after cleaning, making absolute, and resolving symlinked parents.
func samePath(a, b string) (bool, error) {
	if a == "" || b == "" {
		return false, nil
	}
	ca, err := canonicalPath(a)
	if err != nil {
		return false, err
	}
	cb, err := canonicalPath(b)
	if err != nil {
		return false, err
	}
	return ca == cb, nil
}

// rejectPathConflicts ensures named artifact paths do not collide.
func rejectPathConflicts(labeled map[string]string) error {
	keys := make([]string, 0, len(labeled))
	for k, v := range labeled {
		if v != "" {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	for i := 0; i < len(keys); i++ {
		for j := i + 1; j < len(keys); j++ {
			a, b := keys[i], keys[j]
			same, err := samePath(labeled[a], labeled[b])
			if err != nil {
				return err
			}
			if same {
				return fmt.Errorf("%s path %q collides with %s; refuse to overwrite distinct artifacts", a, labeled[a], b)
			}
		}
	}
	return nil
}

func bindArtifactPaths(c bindOptions) map[string]string {
	return map[string]string{
		"--verified-profile": c.verifiedProfile,
		"--policy":           c.policy,
		"--broker-binding":   c.broker,
		"--output":           c.output,
		"--session-out":      c.session,
		"--support-report":   c.supportReport,
	}
}

// outputInputArtifacts is the pre-write collision set: --output versus trusted
// inputs only. Optional outputs are checked after revoke.
func outputInputArtifacts(c bindOptions) map[string]string {
	out := map[string]string{"--output": c.output}
	add := func(label, path string) {
		if path != "" && filepath.IsAbs(path) {
			out[label] = path
		}
	}
	add("--verified-profile", c.verifiedProfile)
	add("--policy", c.policy)
	add("--broker-binding", c.broker)
	return out
}
