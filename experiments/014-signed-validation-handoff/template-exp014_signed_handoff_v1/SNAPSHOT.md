# Packaging snapshot — Experiment 014 Checkpoints 3–8

Template tree `template-exp014_signed_handoff_v1` forked from Experiment 013
`template-exp013_durable_inputs_v3`.

**Live Coder versions**

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
