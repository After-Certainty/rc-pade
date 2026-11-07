---
display_name: Google Compute Engine (Linux)
description: GCE Coder workspaces with signed RC handoff verify then PADE bindings (Experiment 014).
---

# gcp-pade (Experiment 014)

Current live version: `exp014_signed_handoff_v4`.

Exact source for that version is retained in this directory. See [`SNAPSHOT.md`](SNAPSHOT.md)
for the `coder templates pull` capture method and the small repo-only `//go:build ignore` hygiene.

On start:

1. Materialize signed handoff, operator trust/policy/allowlist, and post-verify KnownFields report
2. Verify with pinned `rc-demos` `handoff.Verify` → `verified-profile.yaml`
3. Build/run unchanged Experiment 011 adapter against the verified Profile
4. Write module-managed broker-only bindings (`github.repo.read`, `github.repo.write`)

Trust root is the signed handoff. The validation report is only the unchanged 011 contract after verify succeeds.

Pins: `rc-inputs/SOURCE.txt`. Broker identity only from `module.pade.broker_binding`.
