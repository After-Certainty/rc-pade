---
display_name: Google Compute Engine (Linux)
description: GCE Coder workspaces with signed RC handoff verify then rc-pade bind via pade-coder module (Experiment 015 Checkpoint 2).
---

# gcp-pade (Experiment 015)

Current live version: `exp015_rc_pade_bind_v1`.

On start:

1. Materialize signed handoff, operator trust/policy/allowlist
2. Verify handoff; write `verified-profile.yaml` (sync `after-certainty-rc-trusted-bindings`)
3. Install pinned `rc-pade` with `bind` (sync `after-certainty-rc-pade-install`)
4. `modules/rc-pade-bindings` runs `rc-pade bind --verified-profile` into `module.pade.bindings_path`
