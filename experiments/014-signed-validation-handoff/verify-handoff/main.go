//go:build ignore

// verify-handoff checks an rc-demos validated-profile-handoff bundle under a
// configured public key, then writes the verified Profile bytes.
// It is not an RC validator and does not project or bind PADE capabilities.
// Built against a pinned rc-demos checkout in the Coder template/script, not
// as part of the rc-pade module (see //go:build ignore).
package main

import (
	"crypto/ed25519"
	"fmt"
	"os"

	"github.com/runtimeconditions/rc-demos/validated-profile-handoff/handoff"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: verify-handoff <bundle-dir> <trusted.pub>")
		os.Exit(2)
	}
	pub, err := os.ReadFile(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, "untrusted_handoff trust_configuration_error:", err)
		os.Exit(1)
	}
	profile, err := handoff.Verify(os.Args[1], ed25519.PublicKey(pub))
	if err != nil {
		if f, ok := err.(*handoff.Failure); ok {
			fmt.Fprintf(os.Stderr, "untrusted_handoff %s: %s\n", f.Category, f.Detail)
		} else {
			fmt.Fprintf(os.Stderr, "untrusted_handoff: %s\n", err)
		}
		os.Exit(1)
	}
	out := os.Getenv("VERIFIED_PROFILE_OUT")
	if out == "" {
		out = "verified-profile.yaml"
	}
	if err := os.WriteFile(out, profile, 0o600); err != nil {
		fmt.Fprintln(os.Stderr, "untrusted_handoff write_verified_profile:", err)
		os.Exit(1)
	}
	fmt.Printf("handoff_verified=true profile_sha256=%s bytes=%d out=%s\n", handoff.Digest(profile), len(profile), out)
}
