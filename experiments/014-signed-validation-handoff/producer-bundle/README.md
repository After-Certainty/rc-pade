# Experiment 014 — producer-side signed handoff (Checkpoint 2)

Public artifacts only. **Never** place a private signing key in this directory.

| File | Purpose |
|---|---|
| `profile.yaml` | Exact Experiment 009/011/013 Case A Profile bytes |
| `evidence.json` | Signed handoff claims (`rc-demos-handoff-experiment-1`) |
| `evidence.sig` | Detached Ed25519 signature over exact `evidence.json` bytes |
| `extensions/<sha256>.yaml` | Resolved extension definition bytes bound by evidence |
| `trusted.pub` | Experiment public verification key (32-byte Ed25519) |

Verify with the upstream handoff package against `trusted.pub`. Do not treat
`trusted.pub` from an untrusted download as a production trust anchor; it is
recorded here as the key that signed this experiment bundle.

See `../checkpoint-2-provenance.yaml` for pins, digests, and the private-catalog
adaptation required so `go-rc-profiler/extensioncheck` accepts Case A's
`kind: source_control`.
