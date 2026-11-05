# Experiment 014 — signed Runtime Conditions validation handoff into Coder

**Status:** planned experiment / runbook only. No result is claimed until the steps below are executed and evidence is recorded.

## Question

Can the Coder-side Runtime Conditions consumer verify a signed upstream validation handoff for the exact Profile it receives, then use the unchanged rc-pade / Experiment 011 path to generate PADE bindings and fulfill capabilities — without trusting a locally staged validation report or becoming a Runtime Conditions validator itself?

## Why this experiment exists

Experiment 011 Checkpoint B proved a fresh validation path for the composed Experiment 009 Case A Profile:

```text
Profile
    ↓
fresh rcvalidate
    ↓
byte-bound report
    ↓
deterministic report-shape projection
    ↓
Experiment 011 adapter
    ↓
module-managed PADE bindings
    ↓
PADE broker fulfillment
```

That proves the semantic and binding boundaries, but the validation evidence is still locally available to the consumer and its trust comes from the way the experiment was staged.

Runtime Conditions `rc-demos` PR #5 separately proved a stronger handoff model: upstream generation/resolution/validation produces signed evidence binding exact Profile and resolved-extension bytes, and a downstream consumer verifies the signature and digests before support evaluation.

Reference:

- https://github.com/runtimeconditions/rc-demos/pull/5
- `runtimeconditions/rc-demos/validated-profile-handoff/`

Experiment 014 connects those two proven ideas.

## Dependency

Run Experiment 013 first.

Experiment 013 should establish a durable/operator-controlled delivery mechanism for the trusted inputs needed by a completely fresh Coder workspace.

Experiment 014 should reuse that lifecycle mechanism where appropriate rather than solving durable delivery again.

The new variable introduced here is **cryptographic verification of upstream validation evidence**.

## Hypothesis

A fresh Coder workspace can receive:

- a Runtime Conditions Profile;
- signed evidence binding that exact Profile and the relevant validation inputs;
- only the public verification trust needed by the consumer;

then verify the handoff before rc-pade projection and PADE binding generation.

The consumer should not need access to the signing key and should not need to re-run the full Runtime Conditions validation process to trust the handoff.

Expected shape:

```text
trusted RC producer / CI
        |
        | generate + resolve + validate
        | sign evidence over exact artifacts
        v
Profile + signed validation handoff
        |
        | durable delivery from Experiment 013
        v
fresh Coder workspace
        |
        | verify signature + digests
        v
verified Profile / evidence
        |
        | platform support evaluation
        v
rc-pade projection + allowlist
        |
        v
Experiment 011 adapter / module-managed bindings
        |
        v
PADE Consumer → broker authorization → runtime Material
```

A failed verification must prevent projection/binding generation.

## Trust boundary

The core architectural claim is:

> the downstream platform can trust that the exact Runtime Conditions artifacts it received completed an upstream validation step without the platform becoming that validator.

Signing must not turn Runtime Conditions demand into a PADE grant.

A valid signature means only that trusted upstream validation produced the evidence for those exact artifacts. Platform support policy, PADE broker authorization, and downstream IAM remain independent decisions.

## Non-goals

Do not:

- invent a new Runtime Conditions core resource type;
- standardize the signing/evidence format beyond what is necessary for the experiment;
- move private signing keys into the Coder workspace;
- add RC validation logic to `pade-coder`;
- treat signature verification as platform support or authorization;
- change PADE broker policy merely to get a positive result;
- solve general PKI, key rotation, or organization-wide trust distribution;
- replace the existing rc-demos experiment with a new signing design unless its current contract cannot support the proof.

## Starting point

Before changing anything, inspect the current implementations.

Read:

### rc-pade

- `experiments/009-rc-validated-projection/`
- `experiments/011-coder-rc-bindings/`
- `experiments/013-coder-durable-rc-inputs/README.md`

### rc-demos

- `validated-profile-handoff/README.md`
- `validated-profile-handoff/handoff/evidence.go`
- `validated-profile-handoff/handoff/consume.go`
- `validated-profile-handoff/cmd/validate/main.go`
- `validated-profile-handoff/cmd/consume/main.go`
- the Kratix verifier/gate implementation as useful reference

### pade-coder

- current `modules/pade/main.tf`
- current `modules/pade/README.md`

Treat current implementations as authoritative if they differ from this runbook.

## Checkpoint 1 — define the artifacts being trusted

Identify the minimum artifact set carried from the trusted RC producer to the Coder consumer.

At minimum determine whether the current rc-demos handoff already binds:

- the exact Runtime Conditions Profile bytes;
- resolved extension artifacts/digests;
- validation acceptance;
- validator/tool identity/version where relevant;
- any additional producer metadata required to prevent ambiguous replay or substitution.

Do not add fields merely because they are convenient downstream.

Document which fields are:

- integrity-critical;
- provenance/debugging only;
- platform-local and therefore outside the signed RC handoff.

### Stop condition

If the current rc-demos evidence cannot prove that the exact Profile consumed downstream is the Profile that was accepted upstream, stop and record the gap before integration work.

## Checkpoint 2 — producer-side signed handoff

Use the current rc-demos validated-profile-handoff implementation, or the smallest compatible extraction of it, to produce a signed handoff for the same composed Case A Profile used in Experiments 009 and 011.

Prefer reusing the known `source_control/git` case so this experiment changes only the trust handoff.

Record:

- rc-demos revision;
- Profile SHA-256/byte size;
- resolved extension digests/identifiers as defined by the handoff;
- validator/tool pins;
- signature algorithm/format as already implemented;
- public verification key fingerprint or equivalent non-secret identifier.

Never record the private signing key.

## Checkpoint 3 — durable delivery into fresh Coder

Using the mechanism established by Experiment 013, deliver the following to a completely fresh workspace without manual staging:

- the exact Profile;
- signed evidence;
- any resolved-extension artifacts required by verifier semantics;
- the public verification key/trust material;
- operator-owned projection policy and allowlist;
- actual `pade-coder` broker binding output.

Keep ownership separate:

```text
RC producer/CI:
  Profile + signed validation evidence

platform operator:
  verification trust
  projection policy
  capability allowlist

pade-coder:
  broker binding template
  module-managed bindings path
  synchronization contract
```

## Checkpoint 4 — verify before projection

Run the downstream verification step before rc-pade or the Experiment 011 adapter can consume the Profile.

Verification must check the current rc-demos handoff invariants, including signature and artifact digests.

On success, expose only the verified artifacts to the projection/binding step.

On failure:

- rc-pade must not run on the unverified Profile;
- no capability bindings may be generated;
- the module-managed bindings file must remain empty/fail closed;
- the failure should be classifiable as **untrusted handoff**, distinct from RC-invalid or platform-unsupported demand.

This distinction is important:

```text
bad signature / digest
    → untrusted handoff

trusted evidence says RC validation rejected
    → invalid RC demand

trusted evidence accepts Profile, platform has no mapping/support
    → valid but unsupported demand

trusted + supported demand, broker denies subject
    → authorization denied
```

## Checkpoint 5 — project and bind verified demand

After successful handoff verification, reuse the existing rc-pade projection and Experiment 011 adapter semantics.

Do not introduce a second projection system.

Expected primary Case A output remains:

```text
github.repo.read
github.repo.write
```

Use:

- current Experiment 008/009 projection policy unless intentionally changed and documented;
- current operator allowlist;
- actual `module.pade.broker_binding`;
- actual expanded `module.pade.bindings_path`;
- current `module.pade.scripts` synchronization contract.

Verify mode `0600`, no credential Material, and replacement rather than merge of prior capabilities.

## Checkpoint 6 — live fulfillment

From the verified signed handoff path:

### github.repo.read

Expected:

- handoff verification succeeds;
- projection/binding succeeds;
- broker authorizes the current GCE subject;
- ordinary GitHub read succeeds.

### github.repo.write

Expected for the currently proven subject:

- handoff verification succeeds;
- projection may produce/write the local binding;
- broker denies authorization;
- child does not receive write authority.

This proves that signed validation evidence still does not grant PADE authority.

## Checkpoint 7 — adversarial handoff cases

Exercise the same conceptual cases as the rc-demos validated-profile-handoff proof in the Coder/PADE chain.

At minimum:

1. **valid signed handoff**
   - verifier accepts;
   - projection runs;
   - expected bindings generated;
2. **Profile modified after signing**
   - digest mismatch;
   - projection never runs;
   - bindings empty;
3. **resolved extension artifact changed**
   - verification rejects according to the current evidence contract;
   - projection never runs;
4. **signature from untrusted key / corrupted signature**
   - verification rejects;
   - projection never runs;
5. **trusted and RC-valid but platform-unsupported demand**
   - verification succeeds;
   - rc-pade/platform support step rejects;
   - this must remain distinguishable from an untrusted handoff;
6. **trusted supported demand but broker denial**
   - local binding can exist;
   - broker authorization denies;
   - this must remain distinguishable from all earlier failures.

Do not collapse these outcomes into one generic failure if the evidence allows them to remain distinct.

## Checkpoint 8 — restart / fresh-home proof

Repeat the valid path on a genuinely fresh workspace/home using Experiment 013's durable delivery mechanism.

Expected:

```text
pade-coder initializes empty bindings
        ↓
Profile + signed evidence + public trust arrive automatically
        ↓
signature/digest verification succeeds
        ↓
rc-pade support projection
        ↓
011 adapter replaces real module-managed bindings
        ↓
PADE read succeeds / unauthorized write remains denied
```

No manual staging and no private signing key in the workspace.

## Evidence hygiene

Never record:

- private signing keys;
- JWTs or GCE workload tokens;
- GitHub tokens;
- AWS access key values, secrets, or session tokens;
- numeric Google subject identifiers;
- secret artifact-source credentials.

Safe evidence includes:

- public key fingerprint/public verification material if intentionally public;
- Profile and evidence hashes;
- extension artifact hashes;
- repository/commit pins;
- validator/verifier versions;
- verification outcome;
- capability names;
- authorized/denied outcomes;
- non-sensitive child observations.

## What success proves

Experiment 014 succeeds when a fresh Coder workspace can consume a **signed upstream Runtime Conditions validation handoff**, verify that the exact artifacts it receives were accepted by the trusted upstream validation pipeline, and then use the unchanged rc-pade / Experiment 011 path for platform support evaluation, PADE binding generation, and broker authorization.

It should prove the independence of four decisions:

```text
1. Is this handoff trusted?
2. Is the Runtime Conditions demand valid?
3. Does this platform support/map the demand?
4. Is this runtime subject authorized for the resulting capability?
```

A successful experiment must keep those answers independently observable.

## What success does not prove

It does not establish:

- a normative Runtime Conditions signing format;
- production key management/rotation;
- universal provenance requirements;
- a mandatory validation service architecture;
- PADE as part of Runtime Conditions.

It is implementation evidence for a scalable trust boundary.

## Suggested Cursor workflow

```text
Work interactively through:

experiments/014-signed-validation-handoff/README.md

Experiment 013 should already be complete. Reuse its durable input-delivery mechanism rather than redesigning workspace lifecycle.

Do not implement the entire experiment at once.

Start with Checkpoint 1 only.

For every checkpoint:

1. inspect current rc-demos, rc-pade, pade-coder, and live workspace state;
2. tell me exactly what the existing signed handoff proves;
3. propose the smallest integration step;
4. explain expected evidence and stop conditions;
5. make the change only after I agree;
6. inspect and record the actual result before continuing.

Prefer reuse of runtimeconditions/rc-demos validated-profile-handoff over inventing a new evidence/signing format.

Do not print or persist private signing keys, JWTs, GitHub tokens, AWS credential values, or other secret Material.

Do not conflate handoff verification, RC validity, platform support, and broker authorization.
```
