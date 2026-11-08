# Experiment 015 — dogfood rc-pade bind through the pade-coder optional module

**Status:** Checkpoints 1–7 recorded. Core success met on `exp015_rc_pade_bind_v2`
(workspaces `pade-gcp-015`, `pade-gcp-015-fresh`). Active path is signed handoff
verify → `pade-coder/modules/rc-pade-bindings` → `rc-pade bind` (no Experiment 011
adapter / no `validation-report.yaml`). Live read authorize / write deny preserved.
Canonical provenance: [`checkpoint-1-provenance.yaml`](checkpoint-1-provenance.yaml)
through [`checkpoint-6-provenance.yaml`](checkpoint-6-provenance.yaml); retained
template [`template-exp015_rc_pade_bind_v2/`](template-exp015_rc_pade_bind_v2/).

## Question

Can a real GCE-backed Coder workspace consume the same trusted Runtime
Conditions handoff proven in Experiment 014, pass the resulting verified Profile
through the optional `pade-coder/modules/rc-pade-bindings` module, invoke the
current reusable `rc-pade bind` command, and use the resulting module-managed
PADE bindings end to end?

The target path is:

```text
signed RC handoff
        ↓
handoff verification
        ↓
verified-profile.yaml
        ↓
pade-coder/modules/rc-pade-bindings
        ↓
rc-pade bind
        ↓
module.pade.bindings_path
        ↓
PADE v0.4.1
        ↓
deployed PADE broker
        ↓
github.repo.read  → authorized
github.repo.write → denied
```

## Why this experiment exists

Experiment 014 proved the signed handoff trust boundary in a real Coder
workspace, but its active binding path intentionally reused the historical
Experiment 011 adapter.

That left one compatibility seam:

```text
verified Profile
    ↓
Experiment 011 validation-report contract
    ↓
Experiment 011 adapter
    ↓
module-managed PADE bindings
```

The reusable `rc-pade bind` command removed that validator-specific dependency
from the active rc-pade interface.

Separately, `pade-coder` added the optional
`modules/rc-pade-bindings` helper to orchestrate:

- PADE installation;
- caller-owned Runtime Conditions verification;
- caller-owned rc-pade installation;
- fail-closed binding replacement;
- `rc-pade bind --verified-profile`;
- completion signaling only after successful binding.

Experiment 015 dogfoods those two changes together.

This is not intended to discover a new architecture. It is intended to prove
that the architecture already established by Experiments 013–014 works through
the current reusable interfaces rather than the historical experiment adapter.

## Relationship to pade-coder Experiment 002

`pade-coder/experiments/002-rc-pade-bindings` asks the consumer-side version
of the same live question.

Do **not** run two independent live experiments.

Experiment 015 is the canonical cross-repository provenance trail. The same
live run should satisfy the checkpoints in pade-coder Experiment 002. After
Experiment 015 is complete, update that experiment to point at the recorded 015
evidence rather than duplicating it.

Reference:

- https://github.com/After-Certainty/pade-coder/tree/main/experiments/002-rc-pade-bindings

## Pinned starting revisions

Begin from these known revisions unless current repository state requires a
small documented update:

### rc-pade

```text
43226ef96ae09419b6253a6eb364fd44a0ac1305
```

This is the squash merge that added the reusable validator-independent
`rc-pade bind` command.

### pade-coder

```text
c40ba8c49c987f7b2ea9c1e42eb40fd6c36630a5
```

This is the squash merge that added
`modules/rc-pade-bindings`.

### PADE

Use released PADE v0.4.1, matching the live Experiment 014 path unless a newer
version is intentionally selected and recorded before the experiment begins.

### Runtime Conditions handoff

Reuse the Experiment 014 signed producer bundle, verifier behavior, public trust
material, operator policy, and capability allowlist where possible.

Do not redesign the signing format for Experiment 015.

## Starting point

Before modifying the live Coder template, inspect the current implementation.

Read:

### rc-pade

- `docs/verified-profile-bindings.md`
- `cmd/rc-pade/bind.go`
- `experiments/014-signed-validation-handoff/README.md`
- `experiments/014-signed-validation-handoff/producer-bundle/`
- `experiments/014-signed-validation-handoff/template-exp014_signed_handoff_v4/`

### pade-coder

- `modules/pade/README.md`
- `modules/rc-pade-bindings/README.md`
- `modules/rc-pade-bindings/main.tf`
- `modules/rc-pade-bindings/scripts/bind.sh.tftpl`
- `experiments/002-rc-pade-bindings/README.md`

Treat current implementations as authoritative if they differ from this
runbook. Record any meaningful divergence before proceeding.

## Invariants

Keep these boundaries unchanged throughout the experiment.

### Runtime Conditions trust

The Coder-side verifier decides whether the handoff is trusted.

`rc-pade bind` must receive only the verified Profile output of that step.

### Platform support

`rc-pade` maps already-verified Runtime Conditions demand through explicit
operator policy and allowlist.

It must not become the Runtime Conditions validator.

### Coder lifecycle

`pade-coder` owns synchronization and fail-closed local binding lifecycle.

It must not learn Runtime Conditions validation semantics.

### PADE authorization

Local bindings request capability resolution through the broker.

They do not authorize the workspace subject.

The broker remains responsible for authorization and provider fulfillment.

## Non-goals

Do not:

- change Runtime Conditions semantics;
- invent a new signed-handoff format;
- add validation logic to rc-pade;
- add RC semantics to `modules/pade`;
- move rc-pade installation into the PADE module;
- change PADE broker policy merely to get a positive result;
- broaden the tested capability set beyond what is needed for the existing
  GitHub read/write proof;
- rewrite Experiment 014 provenance;
- remove historical Experiment 011 artifacts;
- claim a general production PKI or release-distribution solution.

The purpose is to replace the **active live integration seam**, not historical
evidence.

## Checkpoint 1 — confirm exact baseline and reusable artifacts

Inspect the current rc-pade, pade-coder, Experiment 014 template snapshot, and
live Coder template state.

Record:

- rc-pade revision;
- pade-coder revision;
- PADE version;
- rc-demos / handoff verifier revision inherited from Experiment 014;
- Profile SHA-256 and byte length;
- signed evidence digest;
- public verification key fingerprint;
- operator policy digest;
- allowlist contents;
- current Coder template/version being used as the baseline;
- current real PADE bindings path;
- existing prerequisite synchronization names.

Confirm that Experiment 014's signed handoff is still reproducible enough to
reuse without changing its trust model.

### Stop condition

If the current live template cannot reproduce the Experiment 014 verification
step, stop and record that lifecycle drift before changing the binding layer.

### Expected provenance

Create:

```text
checkpoint-1-provenance.yaml
```

Do not create it in this setup PR; record it during the live Cursor run.

## Checkpoint 2 — replace only the active binding seam

Starting from the Experiment 014 Coder template, preserve:

- signed handoff materialization;
- public trust material;
- handoff verification;
- verified Profile output;
- operator projection policy;
- operator capability allowlist;
- `module.pade` dynamic mode;
- `module.pade.broker_binding`;
- `module.pade.bindings_path`;
- GCE workload identity;
- deployed broker configuration.

Remove from the **active startup path**:

- build/use of `experiments/011-coder-rc-bindings`;
- adapter-shaped `validation-report.yaml`;
- `--validation-report`;
- validator-specific `rc-extension-resolver` report checks used only by the
  historical 011 adapter.

Add:

- a pinned rc-pade installation step that exposes a Coder sync point;
- the optional `pade-coder/modules/rc-pade-bindings` module;
- prerequisite sync names for successful handoff verification and rc-pade
  installation;
- the actual `module.pade.broker_binding`;
- the actual `module.pade.bindings_path`;
- the existing operator policy and allowlist;
- the exact verified Profile path.

Use approximately this shape, substituting the actual live names and pins:

```tf
module "rc_pade_bindings" {
  source = "git::https://github.com/After-Certainty/pade-coder.git//modules/rc-pade-bindings?ref=c40ba8c49c987f7b2ea9c1e42eb40fd6c36630a5"

  agent_id = coder_agent.main.id

  verified_profile_path = "~/.config/pade/rc-downstream/verified-profile.yaml"
  policy_path           = "~/.config/pade/rc-downstream/policy.yaml"
  allow_capabilities    = ["github.repo.read", "github.repo.write"]

  broker_binding = module.pade.broker_binding
  bindings_path  = module.pade.bindings_path
  pade_scripts   = module.pade.scripts

  prerequisite_scripts = [
    "<actual-handoff-verifier-sync>",
    "<actual-rc-pade-installer-sync>",
  ]

  rc_pade_command = "~/.local/bin/rc-pade"
  session_out     = "~/.config/pade/rc-downstream/development-session.yaml"
}
```

Do not invent synchronization names. Inspect the real template and use the
actual names.

### Static assertions before apply

Confirm the rendered startup path contains:

- `rc-pade bind`;
- `--verified-profile`;
- `module.pade.bindings_path`;
- broker binding derived from `module.pade.broker_binding`;
- waits for PADE install;
- waits for successful handoff verification;
- waits for rc-pade installation.

Confirm it no longer contains in the active path:

- `experiments/011-coder-rc-bindings`;
- `--validation-report`;
- the old report-shape projection helper.

### Expected provenance

Create:

```text
checkpoint-2-provenance.yaml
```

Record template/version pins and non-secret rendered-path observations.

## Checkpoint 3 — fresh/restart happy-path lifecycle

Apply the new template and prove the lifecycle on both:

1. an existing workspace restart/update;
2. a genuinely fresh workspace/home.

Expected sequence:

```text
module.pade starts dynamic mode
        ↓
real bindings become empty
        ↓
signed handoff material arrives
        ↓
handoff verification succeeds
        ↓
verified-profile.yaml is written
        ↓
pinned rc-pade becomes available
        ↓
modules/rc-pade-bindings starts
        ↓
bindings cleared again
        ↓
rc-pade bind succeeds
        ↓
github.repo.read + github.repo.write broker bindings written
        ↓
helper sync completes
```

Verify:

- no manual staging;
- no Experiment 011 adapter binary used;
- no `validation-report.yaml` required;
- bindings file mode is `0600`;
- bindings contain only approved mapped capabilities;
- bindings contain broker configuration only, no credential Material;
- optional DevelopmentSession output, if retained, contains intent only;
- helper sync completion occurs only after successful bind.

Record hashes and modes, not secret contents.

### Expected provenance

Create:

```text
checkpoint-3-provenance.yaml
```

If restart and fresh-home evidence are materially different, split them into
clearly named sections in the same file rather than creating parallel
experiments.

## Checkpoint 4 — live broker authorization

Using the bindings generated specifically by the optional pade-coder module:

### github.repo.read

Expected:

- signed handoff verification succeeds;
- `rc-pade bind` succeeds;
- local broker binding exists;
- PADE v0.4.1 uses the normal module-managed bindings path;
- broker authorizes the GCE subject;
- ordinary GitHub repository read succeeds.

### github.repo.write

Expected for the currently proven subject:

- signed handoff verification succeeds;
- `rc-pade bind` includes the local write binding;
- broker denies the subject;
- child receives no write authority.

Record the denial class/status safely. Do not record bearer tokens or
credential Material.

The important distinction remains:

```text
trusted handoff       ≠ platform support
platform support      ≠ local binding
local binding         ≠ broker authorization
broker authorization  ≠ unrestricted provider authority
```

### Expected provenance

Create:

```text
checkpoint-4-provenance.yaml
```

## Checkpoint 5 — fail-closed real startup failure

After a successful live run, deliberately break one upstream prerequisite.

Preferred case:

- corrupt the signed handoff in the template in the same style used by
  Experiment 014 Checkpoint 7.

Alternative if that is impractical:

- make the pinned rc-pade installer unavailable.

Expected:

- `module.pade` startup clears prior dynamic bindings;
- failed verification or failed rc-pade installation prevents its prerequisite
  sync from completing;
- `modules/rc-pade-bindings` cannot successfully complete;
- the real module-managed bindings path remains `0600`;
- it contains `capabilities: {}`;
- no stale read/write binding survives;
- dependent PADE workloads waiting on the helper do not proceed.

If the helper itself begins and `rc-pade bind` fails, its own fail-closed
replacement must still leave the real bindings empty.

Then restore the valid template and confirm automatic regeneration.

### Expected provenance

Create:

```text
checkpoint-5-provenance.yaml
```

Record both failure and restoration outcomes.

## Checkpoint 6 — compare against Experiment 014 and close the compatibility seam

After the live proof, explicitly compare the Experiment 015 active path with
Experiment 014.

Experiment 014:

```text
signed handoff
  → verify
  → verified Profile
  → compatibility validation-report
  → Experiment 011 adapter
  → PADE bindings
```

Experiment 015 target:

```text
signed handoff
  → verify
  → verified Profile
  → pade-coder optional module
  → rc-pade bind
  → PADE bindings
```

Confirm that the live path no longer requires:

- the Experiment 011 adapter;
- `validation-report.yaml`;
- a validator module name/version in rc-pade's binding interface;
- validator-specific per-condition report shape.

Also confirm what remains intentionally unchanged:

- Experiment 014 signed handoff format is still experimental;
- the producer-side source-control catalog adaptation from Experiment 014, if
  still reused, remains an upstream RC tooling/catalog issue rather than an
  rc-pade binding concern;
- broker authorization behavior is unchanged;
- PADE core remains unaware of Runtime Conditions.

### Expected provenance

Create:

```text
checkpoint-6-provenance.yaml
```

This file should contain the final claim-boundary summary.

## Checkpoint 7 — synchronize consumer-side evidence

Once Checkpoints 1–6 are complete:

1. update this README status with the actual live result;
2. update `experiments/README.md` with the one-line result;
3. update `pade-coder/experiments/002-rc-pade-bindings/README.md` to point at
   Experiment 015 as the canonical live provenance;
4. do not duplicate the same provenance files into pade-coder;
5. record any genuine implementation issue discovered in the appropriate
   owning repository rather than hiding it in experiment notes.

This checkpoint is documentation/evidence reconciliation only.

## Evidence hygiene

Never record:

- private signing keys;
- JWTs or GCE workload tokens;
- Coder session tokens;
- GitHub tokens;
- GitHub Material values;
- AWS access keys, secrets, or session tokens;
- numeric Google subject identifiers;
- secret artifact-source credentials.

Safe evidence includes:

- public repository/commit pins;
- public verification-key fingerprint;
- Profile/evidence/policy hashes;
- rc-pade and PADE versions;
- Coder template/version names;
- bindings path, mode, and digest;
- capability names;
- synchronization names;
- verifier/bind success or failure;
- broker authorization/denial outcomes;
- non-sensitive child observations.

## What success proves

Experiment 015 succeeds when a real GCE-backed Coder lifecycle can use the
current reusable boundaries:

```text
trusted signed RC handoff
        ↓
verified Profile bytes
        ↓
pade-coder optional bindings module
        ↓
rc-pade bind
        ↓
module-managed PADE bindings
        ↓
PADE v0.4.1
        ↓
broker authorization
```

with:

- no active Experiment 011 adapter;
- no active validator-specific `validation-report.yaml`;
- no manual bindings staging;
- restart and fresh-home regeneration;
- fail-closed startup behavior;
- live read authorization;
- live write denial.

This would close the Coder-side compatibility seam identified by Experiment 014
and dogfood both the rc-pade and pade-coder cleanup work in one real integration.

## What success does not prove

It does not establish:

- a normative Runtime Conditions signing format;
- production signing-key lifecycle or PKI;
- a production rc-pade distribution/update mechanism;
- universal Coder compatibility;
- support for every Runtime Conditions extension;
- that stock RC extension catalogs validate the Experiment 014 Case A Profile
  without its documented producer adaptation;
- that local PADE bindings grant authority;
- that PADE or pade-coder should own Runtime Conditions semantics.

## Suggested Cursor workflow

Work interactively through:

```text
experiments/015-pade-coder-rc-pade-bind-dogfood/README.md
```

Do not implement the entire experiment at once.

Start with **Checkpoint 1 only**.

For every checkpoint:

1. inspect current rc-pade, pade-coder, Experiment 014 artifacts, and live Coder
   state;
2. report any difference from the pinned assumptions in this runbook;
3. propose the smallest change needed for that checkpoint;
4. explain the expected evidence and stop conditions;
5. make the change only after I agree;
6. inspect the actual live result;
7. create or update only that checkpoint's provenance file;
8. stop before the next checkpoint.

Prefer reusing the exact Experiment 014 signed handoff and trust material over
inventing new signing or validation behavior.

Use `pade-coder/modules/rc-pade-bindings` as implemented. Do not copy its shell
logic into the Coder template.

Do not restore `validation-report.yaml` merely to make the old 011 adapter
work. If a hidden dependency on that report remains, stop and record it as an
Experiment 015 finding.

Do not print or persist private signing keys, JWTs, GitHub tokens, AWS credential
values, Coder session tokens, or other secret Material.

Keep these decisions independently observable:

```text
1. Is the RC handoff trusted?
2. Does rc-pade support/map the verified demand?
3. Did the pade-coder binding lifecycle complete?
4. Is the runtime subject authorized by the PADE broker?
```
