package main

import (
	"fmt"
	"path/filepath"
	"sort"
)

// samePath reports whether two filesystem paths refer to the same location
// after cleaning and making absolute. Symlinks are not resolved.
func samePath(a, b string) (bool, error) {
	if a == "" || b == "" {
		return false, nil
	}
	absA, err := filepath.Abs(a)
	if err != nil {
		return false, err
	}
	absB, err := filepath.Abs(b)
	if err != nil {
		return false, err
	}
	return filepath.Clean(absA) == filepath.Clean(absB), nil
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
