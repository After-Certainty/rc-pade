# Packaging snapshot — Experiment 015 Checkpoint 2 template

Directory `template-exp015_rc_pade_bind_v1` is the retained source for the
live Coder template version **`exp015_rc_pade_bind_v1`**.

## Capture method

```text
coder templates push gcp-pade --directory <this-dir> --name exp015_rc_pade_bind_v1 --activate=true --yes
coder templates pull gcp-pade <dest> --version exp015_rc_pade_bind_v1 --yes
```

| Field | Value |
|---|---|
| template | `gcp-pade` |
| version | `exp015_rc_pade_bind_v1` |
| live active | true |
| exact unmodified pull file-manifest SHA-256 | `65b6bfdbd7850bacbb09b114d5f1520d5096be3e3ab8b4dedef5bab94ab0c755` |
| retained tree manifest SHA-256 | `65b6bfdbd7850bacbb09b114d5f1520d5096be3e3ab8b4dedef5bab94ab0c755` |
| baseline | `exp014_signed_handoff_v4` (manifest `59bac334aa050ad34a0b5070f8546f066210d17f2e85e054e00a6cebafba1a00`) |

## Behavior at v1

1. Materialize signed handoff + operator trust/policy/allowlist
2. Verify handoff; write `verified-profile.yaml` (sync `after-certainty-rc-trusted-bindings`)
3. Install pinned `rc-pade` @ `43226ef` to `~/.local/bin/rc-pade` (sync `after-certainty-rc-pade-install`)
4. `modules/rc-pade-bindings` @ `c40ba8c` runs `rc-pade bind --verified-profile` into `module.pade.bindings_path`

No Experiment 011 adapter. No `validation-report.yaml` in the active path.

## Digests

- per-file: [`FILE-DIGESTS.sha256`](FILE-DIGESTS.sha256)

## Secrets

No private signing keys embedded. `trusted.pub` is the experiment public key only.
