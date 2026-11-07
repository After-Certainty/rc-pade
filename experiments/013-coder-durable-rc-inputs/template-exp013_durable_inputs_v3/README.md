---
display_name: Google Compute Engine (Linux)
description: Provision Google Compute Engine instances as Coder workspaces with PADE dynamic bindings and durable RC trusted-input delivery (Experiment 013).
---

# gcp-pade

GCE-backed Coder workspace template for PADE with dynamic empty bindings and a trusted RC downstream `coder_script` that:

1. sync-wants PADE install;
2. expands `module.pade.bindings_path`;
3. materializes `module.pade.broker_binding`;
4. materializes operator-/pipeline-pinned Profile, validation evidence, projection policy, allowlist, and Experiment 011 adapter from template-embedded `rc-inputs/`;
5. runs the Experiment 011 adapter against the real module-managed bindings path.

Pinned input digests are recorded in `rc-inputs/SOURCE.txt`. Broker endpoint/audience/identity are never duplicated outside `module.pade.broker_binding`.
