# Experiment 011 — `pade-coder` module-managed handoff follow-up

**Status:** Checkpoint A recorded in [`checkpoint-a-provenance.yaml`](./checkpoint-a-provenance.yaml). Checkpoint B recorded in [`checkpoint-b-provenance.yaml`](./checkpoint-b-provenance.yaml) (B1 records both S3 reject and Case A accept).

## Purpose

Experiment 011 proved that its trusted adapter can turn validated-shaped Runtime Conditions demand plus operator policy into broker-only PADE bindings, and that those bindings can fulfill real `github.repo.read` and `aws.s3.bucket.write` capabilities from a GCE-backed Coder workspace.

The live proof deliberately used absolute temporary binding paths under `/tmp/experiment-011-live*`.

This follow-up closes the remaining Coder integration gap by exercising the actual generic `pade-coder` downstream-integration contract:

```text
pade-coder
    |
    | installs PADE
    | initializes empty dynamic bindings
    | exposes broker_binding
    | exposes bindings_path
    | exposes scripts
    v
trusted RC downstream integration
    |
    | waits for PADE installation
    | validates trusted demand
    | projects supported demand
    | applies operator allowlist
    | atomically replaces module-managed bindings
    v
~/.config/pade/coder-bindings.yaml
    |
    v
PADE Consumer
    |
    v
broker authorization
    |
    v
runtime Material
```

The goal is not to add Runtime Conditions awareness to `pade-coder`. The module remains a generic PADE substrate.

## Current `pade-coder` contract

Before execution, inspect the current `After-Certainty/pade-coder` `modules/pade` implementation rather than relying only on this document.

At the time this runbook was written, the contract includes:

- `broker_capabilities = []` for dynamic downstream bindings;
- `module.pade.broker_binding` — non-secret broker provider/endpoint/audience/identity configuration;
- `module.pade.bindings_path` — module-managed `~/.config/pade/coder-bindings.yaml`;
- `module.pade.scripts` — Coder synchronization prerequisites for dependent scripts;
- PADE v0.4.1 as the module default.

The module documentation requires a trusted downstream integration to atomically replace the module-managed bindings file with mode `0600` only after PADE installation has completed and before dependent PADE workloads start.

Do not duplicate derived capability names in the Coder template.

Reference:

- https://github.com/After-Certainty/pade-coder/tree/main/modules/pade

## Checkpoint A — actual Coder handoff

Checkpoint A isolates the Coder integration seam. It may reuse an already-proven valid Profile/evidence path so that failures can be attributed to the module handoff rather than to a new validation mechanism.

### A1. Inspect before changing anything

Record:

- Coder template/repository and revision;
- current `pade-coder` source/revision;
- current PADE version;
- workspace name and runtime;
- configured broker endpoint, audience, and identity adapter;
- whether static `broker_capabilities` are currently configured;
- current value, contents, and permissions of the module-managed bindings path.

Do not print identity tokens or provider credentials.

Do not modify the template or workspace until the current state is understood.

### A2. Configure dynamic PADE bindings

Use the generic PADE module with no static capabilities:

```hcl
broker_capabilities = []
```

or omit the input if the current module default is still empty.

After the `pade-coder` install step completes, the expected module-managed bindings state is:

```yaml
version: "0.1"
capabilities: {}
```

at the expanded absolute form of:

```text
module.pade.bindings_path
```

with file mode `0600`.

Do not continue if stale capabilities remain.

### A3. Consume the real module outputs

The downstream Runtime Conditions integration must consume, rather than independently reconstruct:

```text
module.pade.broker_binding
module.pade.bindings_path
module.pade.scripts
```

Requirements:

- serialize `module.pade.broker_binding` as the JSON object expected by the Experiment 011 adapter;
- expand `~` in `module.pade.bindings_path` at runtime before passing it as `--output`, because the adapter requires an absolute path;
- wait for the PADE installation pipeline represented by `module.pade.scripts` before invoking the adapter.

The current `pade-coder` documentation describes dependent scripts using the Coder synchronization contract conceptually as:

```text
coder exp sync want <self> <module.pade.scripts...>
```

Inspect the current Coder/`coder-utils` behavior and existing module examples before writing the dependent script. Do not guess the dependent script's synchronization identity or lifecycle semantics.

### A4. Run the existing Experiment 011 adapter

Invoke the adapter in:

```text
experiments/011-coder-rc-bindings
```

with:

```text
--profile
--validation-report
--policy
--broker-binding
--allow-capabilities
--output
--session-out
```

where:

- the Profile/evidence are trusted and byte-bound;
- projection policy is operator-owned;
- the capability allowlist is operator-owned;
- broker binding comes directly from `module.pade.broker_binding`;
- output is the expanded absolute `module.pade.bindings_path`.

The adapter must retain its existing fail-closed behavior.

Do not change Experiment 011 adapter semantics merely to make this follow-up pass.

### A5. Verify the module-managed bindings file

Confirm:

- the output path is the actual expanded `module.pade.bindings_path`;
- file mode is `0600`;
- only projected and allowlisted capability names exist;
- every capability is broker-bound;
- no credential Material is present;
- no stale capability survives from a previous run.

A failed or incomplete adapter invocation must leave the module-managed file with no usable capability bindings.

### A6. Exercise PADE through normal module configuration

Do not use the previous Experiment 011 temporary `--bindings /tmp/...` override for the primary proof.

From a normal workspace shell, first verify which bindings path PADE will consume. Then run the normal PADE validation/planning flow against the generated DevelopmentSession using the current installed PADE release.

Exercise:

```text
github.repo.read
```

Expected:

- local binding is present;
- broker authorization succeeds;
- ordinary GitHub read succeeds.

Exercise:

```text
github.repo.write
```

Expected for the currently proven GCE subject:

- local binding may be present because it is projected and allowlisted;
- broker authorization denies the request;
- no write capability is obtained.

This distinction is part of the proof: local bindings are resolution configuration, not authorization grants.

Optionally repeat the previously proven:

```text
aws.s3.bucket.write
```

flow and retain its existing least-privilege negative checks:

- allowed-prefix `PutObject` succeeds;
- outside-prefix `PutObject` is denied;
- bucket listing is denied;
- no ambient durable AWS credentials are present before PADE execution.

### A7. Restart proof

Restart the Coder workspace and observe the actual ordering rather than assuming it:

```text
pade-coder dynamic startup
    ↓
empty module-managed bindings
    ↓
PADE install/synchronization completes
    ↓
trusted RC downstream integration runs
    ↓
module-managed bindings regenerated
    ↓
dependent PADE workload may start
```

Verify:

- stale bindings do not survive a failed or incomplete startup;
- the trusted downstream step does not run before the PADE module prerequisites complete;
- a dependent workload cannot race ahead of the trusted binding-generation step if the intended integration requires those bindings.

If the ordering cannot be demonstrated clearly, stop and record that as an integration finding rather than adding ad hoc delays.

## Checkpoint B — fresh validation handoff

Checkpoint B strengthens the upstream trust boundary only after Checkpoint A proves the Coder handoff.

Experiment 011's original live run reused validation-shaped evidence. The next proof should begin from a fresh trusted validation of the exact Profile bytes consumed by the adapter.

Experiment 009 already contains a wrapper around:

```text
github.com/runtimeconditions/rc-extension-resolver
```

that validates a Profile and records byte-bound evidence.

The required invariant is:

```text
Profile bytes
    ↓
trusted RC validation
    ↓
accepted hash/evidence
    ↓
same exact Profile bytes
    ↓
Experiment 011 adapter
```

The adapter remains a consumer of trusted validation evidence. It must not become the Runtime Conditions validator.

Reference:

- `experiments/009-rc-validated-projection/`

### Optional stronger trust-handoff follow-up

The Runtime Conditions `rc-demos` trusted-handoff experiment proves a stronger model in which upstream generation/resolution/validation produces signed evidence and a downstream consumer verifies that evidence before support evaluation.

Reference:

- https://github.com/runtimeconditions/rc-demos/pull/5

That signed handoff is useful evidence for a production-grade boundary, but it is not required to prove the `pade-coder` module handoff in Checkpoint A. Do not add signing infrastructure merely to make this follow-up succeed.

## Stop conditions

Stop and record the boundary rather than patching around it if:

- `pade-coder` outputs cannot be consumed without duplicating operator configuration;
- downstream ordering cannot reliably wait for PADE installation;
- the module-managed bindings file cannot be atomically replaced with the expected ownership/mode;
- restart behavior exposes stale usable bindings;
- the adapter requires unchecked repository-controlled input;
- generated bindings contain capabilities outside the projection and operator allowlist;
- a local binding behaves like an authorization grant;
- normal PADE use still requires a temporary bindings override;
- fresh validation cannot be tied to the exact Profile bytes passed to the adapter.

## Evidence hygiene

Never record:

- JWTs or workload identity tokens;
- GitHub tokens;
- AWS access key values, secret keys, or session tokens;
- numeric Google subject identifiers;
- other provider credential Material.

Avoid recording account identifiers that are not necessary to explain or reproduce the experiment.

Safe evidence includes:

- repository and commit pins;
- module and PADE versions;
- workspace/runtime class;
- binding path and file mode;
- capability names;
- authorized/denied outcomes;
- non-sensitive HTTP status;
- successful GitHub repository name;
- S3 experiment key/prefix;
- presence/absence booleans for Material;
- temporary-credential classification such as the AWS `ASIA` prefix without the credential value.

## Success criteria

### Checkpoint A

Checkpoint A succeeds when the actual `pade-coder` module outputs and synchronization contract drive the existing Experiment 011 adapter to replace the real module-managed bindings file, and normal PADE consumption from the Coder workspace demonstrates broker-authorized capability use while preserving broker denial of unauthorized intent.

### Checkpoint B

Checkpoint B succeeds when the same flow begins from a fresh trusted validation of the exact Profile bytes consumed by the adapter.

Neither checkpoint changes Runtime Conditions semantics, PADE authorization semantics, or the generic `pade-coder` responsibility boundary.

## Suggested interactive Cursor workflow

This runbook is intentionally written for stepwise execution in the live Coder environment.

A useful starting prompt is:

```text
Work interactively through:

experiments/011-coder-rc-bindings/pade-coder-handoff-followup.md

Do not implement the entire runbook at once.

Start by inspecting the current state of:

- the live Coder template used by the pade-gcp workspace;
- After-Certainty/pade-coder main, especially modules/pade/main.tf and README.md;
- Experiment 011;
- Experiment 009 validation tooling.

For every step:

1. tell me what you found;
2. tell me exactly what we are about to change or run;
3. explain what result we expect and what would make us stop;
4. make only that change or run only that command after I agree;
5. inspect the actual result before advancing.

Use the current repository implementations as authoritative if they differ from the runbook.

Do not print or persist JWTs, GitHub tokens, AWS credential values, or other secret Material.

Do not broaden scope into redesigning Runtime Conditions, PADE, or pade-coder.

Begin with Checkpoint A1 only.
```
