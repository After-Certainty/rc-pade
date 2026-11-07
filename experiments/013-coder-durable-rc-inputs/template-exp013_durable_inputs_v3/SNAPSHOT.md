# Sanitized snapshot of Coder template `gcp-pade` @ `exp013_durable_inputs_v3`

This is the exact Terraform / `coder_script.rc_trusted_bindings` source used for
Experiment 013 Checkpoints 3–7 live proofs, pulled via:

```text
coder templates pull gcp-pade --version exp013_durable_inputs_v3
```

## What this preserves

- embedding/materialization of `rc-inputs/` fixtures;
- pinned Go + `rc-pade` adapter fetch/build;
- `coder exp sync want` on `module.pade.scripts`;
- `broker_binding.json` from `module.pade.broker_binding` only;
- Experiment 011 adapter invocation against `module.pade.bindings_path`.

## Digests

- tar stream of snapshot contents (excluding this file and FILE-DIGESTS.sha256): `c715c4cb10b58e433d7076caacf3c4435cd3d9ab10f401b8d1131fb36415df33`
- per-file digests: [`FILE-DIGESTS.sha256`](FILE-DIGESTS.sha256)

## Secrets

No provider secrets or identity tokens are embedded. Broker endpoint/audience/identity
are interpolated at apply time from `module.pade.broker_binding`, not hardcoded here.
Template Terraform variables (`project_id`, `pade_broker_endpoint`) remain operator-supplied
at template push / workspace create time and are not recorded in this snapshot.
