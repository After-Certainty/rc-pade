# Packaging snapshot — Experiment 014 final live template

Directory `template-exp014_signed_handoff_v4` is the retained source for the
live Coder template version **`exp014_signed_handoff_v4`** that closed
Checkpoints 5–8.

## Capture method

```text
coder templates pull gcp-pade <dest> --version exp014_signed_handoff_v4 --yes
```

Recorded at capture:

| Field | Value |
|---|---|
| template | `gcp-pade` |
| version | `exp014_signed_handoff_v4` |
| exact unmodified pull file-manifest SHA-256 | `59bac334aa050ad34a0b5070f8546f066210d17f2e85e054e00a6cebafba1a00` |
| capture command | `coder templates pull … --version exp014_signed_handoff_v4` |

## Repo hygiene applied after pull (only)

So `go test ./...` in this module does not require `rc-demos`:

1. `//go:build ignore` on `rc-inputs/verify-handoff/main.go`
2. template script strips that tag before `go build` inside the pinned rc-demos checkout

No handoff bytes, policy, allowlist, or broker wiring were changed after the pull.

## Live version history

| Version | Result |
|---|---|
| `exp014_signed_handoff_v1` | Failed import (`file()` on binary sig/pub) |
| `exp014_signed_handoff_v2` | CP3 packaging materialization |
| `exp014_signed_handoff_v3` | CP4 verify-before-projection |
| `exp014_signed_handoff_v4` | CP5–8 verify → unchanged 011 project/bind; live + adversarial + restart/fresh (active) |

## Behavior at v4

1. Materialize signed handoff + operator trust/policy/allowlist + post-verify KnownFields report
2. Build/run `handoff.Verify`; write `verified-profile.yaml`
3. Build/run Experiment 011 adapter on verified Profile only after verify
4. Fail-closed empty bindings on `untrusted_handoff` (never invoke adapter)

## Digests

- per-file: [`FILE-DIGESTS.sha256`](FILE-DIGESTS.sha256)

## Secrets

No private signing keys embedded. `trusted.pub` is the experiment public key only.
