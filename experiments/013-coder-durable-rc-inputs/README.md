# Experiment 013 — durable trusted Runtime Conditions inputs for fresh Coder workspaces

**Status:** Checkpoints 1–3 recorded. Durable template delivery proven on `pade-gcp-013` / `exp013_durable_inputs_v3` (fixtures + pinned adapter build; no manual staging). Live fulfillment evidence remains Checkpoint 4/5.

## Question

Can a completely fresh GCE-backed Coder workspace obtain the operator-controlled inputs required by the Experiment 011 trusted Runtime Conditions integration from a durable source and automatically regenerate the real `pade-coder` module-managed bindings file without any manual staging?

## Why this experiment exists

Experiment 011 proved the downstream handoff:

```text
validated Runtime Conditions demand
        ↓
rc-pade projection + operator allowlist
        ↓
Experiment 011 trusted adapter
        ↓
module-managed PADE bindings
        ↓
PADE Consumer
        ↓
broker authorization
        ↓
runtime Material
```

Its restart checkpoint also exposed the next lifecycle boundary.

On a fresh workspace home, `pade-coder` correctly initialized empty bindings and the trusted downstream script correctly waited for PADE installation, but the integration stopped because its operator-owned inputs were no longer present under `~/.config/pade/rc-downstream/`. After those inputs were manually restaged, the same handoff succeeded.

Experiment 013 tests only how those trusted inputs arrive on a fresh workspace.

It does **not** redesign Runtime Conditions, rc-pade projection, PADE authorization, or the Experiment 011 adapter.

## Hypothesis

A Coder-side integration can obtain the trusted inputs it needs from a durable, operator-controlled source during workspace startup, then feed those inputs into the unchanged Experiment 011 adapter after `pade-coder` completes.

A successful flow should look like:

```text
fresh Coder workspace / empty home
        ↓
pade-coder dynamic startup
        ↓
empty module-managed bindings
        ↓
trusted operator input delivery
        ↓
Profile + validation evidence + policy + allowlist + broker template
        ↓
Experiment 011 adapter
        ↓
module-managed bindings
        ↓
PADE Consumer
        ↓
broker authorization
```

No manual copy into the new workspace should be required.

## Scope

This experiment should determine the smallest reliable source-of-truth and delivery contract for the trusted downstream inputs used by Experiment 011.

Inputs include, as applicable:

- the Runtime Conditions Profile to be consumed;
- byte-bound trusted validation evidence for that Profile;
- the operator-owned rc-pade projection policy;
- the operator-owned capability allowlist;
- the broker binding configuration derived from `module.pade.broker_binding`;
- the Experiment 011 adapter executable/source required to perform the handoff.

The experiment may use an existing Coder/Terraform mechanism, an operator-controlled repository/artifact, or another durable source already appropriate for the environment.

Prefer the smallest mechanism that demonstrates ownership and lifecycle clearly.

## Non-goals

Do not:

- add Runtime Conditions parsing or semantics to `pade-coder`;
- add capability mappings to the Coder template;
- turn portable workload demand into authorization;
- modify broker policy or downstream IAM merely to make the experiment pass;
- solve signed cross-system validation provenance here — that is Experiment 014;
- introduce a general-purpose secret/config distribution platform;
- change the Experiment 011 adapter unless an actual contract defect is discovered and recorded.

## Starting point

Before changing anything, inspect current `main` and the live Coder template/workspace.

Read:

- `experiments/011-coder-rc-bindings/README.md`
- `experiments/011-coder-rc-bindings/pade-coder-handoff-followup.md`
- `experiments/011-coder-rc-bindings/checkpoint-a-provenance.yaml`
- `experiments/011-coder-rc-bindings/checkpoint-b-provenance.yaml`
- `After-Certainty/pade-coder` `modules/pade/main.tf` and `README.md`

Treat current repository implementations as authoritative if they differ from this runbook.

## Checkpoint 1 — identify ownership and durable source

Document exactly who owns each trusted input and where it should live before a workspace exists.

At minimum classify:

| Input | Expected owner | Portable workload input? | Operator-controlled? | Durable source chosen |
|---|---|---:|---:|---|
| Runtime Conditions Profile | workload / trusted pipeline | yes | may be produced by trusted pipeline | Coder template–pinned trusted bytes (011 B Case A) |
| validation evidence | trusted validation pipeline | no | yes | Coder template–pinned projected report (011 B2) |
| projection policy | platform operator | no | yes | Coder template (Terraform-controlled) |
| capability allowlist | platform operator | no | yes | Coder template (Terraform-controlled) |
| broker binding template | Coder / platform operator | no | yes | `module.pade.broker_binding` (already durable) |
| adapter | platform integration | no | yes | pinned `rc-pade` commit fetch + pinned Go build (template archive ≤1MiB) |

**Checkpoint 1 recorded:** [`checkpoint-1-provenance.yaml`](checkpoint-1-provenance.yaml). Chosen mechanism: extend existing `coder_script.rc_trusted_bindings` so remaining inputs are materialized from operator-controlled template content the same way `broker_binding` already is. Ownership split is clear — continue.

The chosen mechanism must not require a human to SSH into the workspace and recreate files after every fresh home.

### Stop condition

If the design cannot clearly distinguish workload-owned demand from operator-owned support/binding policy, stop and record the ambiguity before implementation.

## Checkpoint 2 — provision a completely fresh workspace

Create or recreate the GCE-backed Coder workspace with a fresh home.

Before the trusted RC step runs, verify:

- PADE version and `pade-coder` revision;
- `broker_capabilities = []` or equivalent current dynamic configuration;
- the real `module.pade.bindings_path` contains an empty capability map;
- file mode is `0600`;
- no prior `~/.config/pade/rc-downstream/` staging has survived;
- no ambient GitHub or AWS provider credentials are present.

Do not manually place Profile, evidence, policy, or allowlist files in the workspace.

**Checkpoint 2 recorded:** [`checkpoint-2-provenance.yaml`](checkpoint-2-provenance.yaml) on fresh workspace `pade-gcp-013` / `lucky_morgan36`. Empty module-managed bindings (`capabilities: {}`, mode `0600`); only script-written `broker_binding.json` under `rc-downstream/`; adapter/profile/report/policy/allow absent; RC script STOP; no ambient GitHub/AWS provider credentials. Prior `pade-gcp` retained as the interactive push host.

## Checkpoint 3 — deliver trusted inputs automatically

Use the chosen durable source to deliver or materialize the trusted inputs.

Requirements:

- delivery occurs through the Coder/platform integration, not through a manual shell copy;
- repository-controlled workload content alone must not be able to rewrite operator projection policy or allowlist;
- broker endpoint/audience/identity must still come from the actual `pade-coder` module output rather than a duplicated value;
- resulting local files, if any, should have appropriate restrictive permissions;
- failure to retrieve any required trusted input must leave PADE bindings empty.

Record source identifiers, revisions/digests, and resulting local paths without recording secret Material.

**Checkpoint 3 recorded:** [`checkpoint-3-provenance.yaml`](checkpoint-3-provenance.yaml). Template `exp013_durable_inputs_v3` materializes Profile/report/policy/allowlist from embedded `rc-inputs/` (mode `0600`, digests match fixtures), builds the Experiment 011 adapter from pinned `rc-pade` @ `fd592a4` with pinned Go `1.26.10`, and keeps broker binding on `module.pade.broker_binding` only. No manual shell copy. Fixtures live under [`fixtures/`](fixtures/).

## Checkpoint 4 — run the unchanged Experiment 011 handoff

After `module.pade.scripts` prerequisites complete and the trusted inputs are present, run the existing Experiment 011 adapter.

Use the same fail-closed contract already proven in 011.

The primary path should use the real:

```text
module.pade.broker_binding
module.pade.bindings_path
module.pade.scripts
```

Do not use a temporary bindings path for the primary proof.

Verify the resulting module-managed file:

- mode `0600`;
- only approved projected capabilities;
- broker-only configuration;
- no credential Material;
- no stale capabilities.

## Checkpoint 5 — live fulfillment

Use the currently supported fresh-validation path from Experiment 011 Checkpoint B unless a newer equivalent exists.

At minimum exercise:

```text
github.repo.read
```

Expected:

- local binding exists;
- broker authorizes the current GCE subject;
- ordinary GitHub read succeeds.

Also exercise:

```text
github.repo.write
```

Expected for the currently proven subject:

- local binding may exist;
- broker denies the request;
- child command does not receive write authority.

The purpose is to verify the automatically delivered trusted inputs reach the already-proven authorization boundary unchanged.

Do not expand broker authorization just to produce a positive write result.

## Checkpoint 6 — failure cases

From fresh or restarted workspaces, test at least:

1. **durable source unavailable**
   - expected: no usable bindings;
2. **missing projection policy**
   - expected: no usable bindings;
3. **missing allowlist**
   - expected: no usable bindings;
4. **tampered Profile after validation**
   - expected: adapter rejects byte mismatch and bindings remain empty;
5. **tampered validation evidence**
   - expected: adapter rejects and bindings remain empty;
6. **operator policy does not approve a projected capability**
   - expected: adapter rejects and bindings remain empty.

Do not weaken validation or fail-closed behavior to make startup continue.

## Checkpoint 7 — restart and recreate

Prove both cases separately:

### Restart with persistent trusted source

Restart the workspace.

Expected:

```text
pade-coder clears/initializes bindings
        ↓
trusted inputs automatically available again
        ↓
011 handoff regenerates bindings
        ↓
dependent PADE workload proceeds
```

### Full recreate / fresh home

Destroy/recreate the workspace or otherwise reproduce a genuinely fresh home.

Expected:

- no manual staging;
- trusted inputs are obtained automatically from their durable source;
- bindings regenerate successfully;
- the same read/deny boundary still holds.

This is the core success criterion for Experiment 013.

## Evidence hygiene

Never record:

- JWTs or GCE identity tokens;
- GitHub tokens;
- AWS access key values, secret keys, or session tokens;
- numeric Google subject identifiers;
- secret artifact credentials.

Safe evidence includes:

- repository/artifact identifiers and immutable revisions;
- hashes/digests;
- module/template versions;
- workspace/runtime class;
- file paths and modes;
- capability names;
- authorized/denied outcomes;
- non-sensitive child observations.

## What success proves

Experiment 013 succeeds when a brand-new Coder workspace can move from empty dynamic PADE bindings to the same trusted Runtime Conditions → rc-pade → PADE handoff proven in Experiment 011 **without any manual restaging of trusted inputs**.

It should establish:

- who owns the trusted inputs;
- where they live durably;
- how a fresh workspace obtains them;
- how failure stays fail-closed;
- that the existing downstream authorization boundary remains unchanged.

It does **not** prove a signed cross-system validation handoff. That is intentionally reserved for Experiment 014.

## Suggested Cursor workflow

```text
Work interactively through:

experiments/013-coder-durable-rc-inputs/README.md

Do not implement the entire experiment at once.

Start with Checkpoint 1 only.

For every checkpoint:

1. inspect the current repositories/template/workspace first;
2. tell me what you found;
3. propose the smallest next change;
4. explain the expected evidence and stop conditions;
5. make the change only after I agree;
6. inspect and record the actual result before continuing.

Use current main implementations as authoritative if they differ from this runbook.

Do not print or persist JWTs, GitHub tokens, AWS credential values, or other secret Material.

Do not broaden scope into signed validation handoff; that is Experiment 014.
```
