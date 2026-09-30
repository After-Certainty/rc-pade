# Experiment 010 — resolved semantic identity across the validation boundary

**Status: design scaffold only. No executable experiment yet. Production rc-pade changes: zero.**

## Question

Experiment 009 established that Runtime Conditions resolution/validation can run as an upstream gate before an unchanged `rc-pade`, and that RC semantic validity is distinct from platform capability support.

Experiment 010 asks the next boundary question:

> After a Runtime Conditions Profile has been resolved and validated, is the validated Condition vocabulary itself sufficient for safe downstream platform interpretation, or must some resolved semantic identity/provenance survive validation so the platform knows exactly which semantic contract it is acting on?

The concrete pressure is that `rc-pade` currently classifies Conditions using `kind + interfaceType`.

For example, if two different immutable extensions can each define semantically different vocabulary that appears downstream as:

```yaml
kind: source_control
interface:
  type: git
  provider: github
  access: [push]
```

then a consumer matching only `source_control + git` may be unable to distinguish two different semantic contracts.

Experiment 010 should determine whether that substitution is legal and meaningful under Runtime Conditions semantics before adding any identity-aware behavior to `rc-pade`.

## Starting point

Experiment 009 demonstrated this boundary:

```text
RuntimeConditionsProfile
        ↓
RC resolution + validation
        ↓
same Profile bytes
        ↓
unchanged rc-pade
        ↓
platform projection policy
```

009 established that:

- RC-invalid semantics can be rejected before `rc-pade`.
- RC-valid but platform-unsupported semantics can fail later at platform policy.
- `rc-pade` does not need to load extension artifacts for the tested `source_control/git` case.
- Validation is currently a pipeline property; no validation attestation was introduced.
- Nothing in 009 established whether resolved extension identity must survive that boundary.

The Experiment 009 investigation also recorded several unresolved implementation observations around ambiguous kinds, explicit selectors, provenance fidelity, validator divergence, and cross-Profile semantic substitution. Those are inputs to 010, not assumptions.

## Candidate hypothesis

Start with the weaker hypothesis:

> A downstream platform can safely interpret an RC-validated Condition using the validated vocabulary plus platform policy, without carrying resolved extension identity into projection.

A useful falsification would be:

> Two separately accepted Profiles contain the same `(kind, interfaceType)` and compatible field shape, but those semantics resolve from different extension identities and are not semantically interchangeable. An unchanged `rc-pade` projects them identically.

If such a case is valid under the RC spec, validated vocabulary alone is not enough for safe platform interpretation.

If the RC spec prevents that case, identify the invariant that prevents it instead of inventing an identity gate.

## What 010 must distinguish

Do not treat these as equivalent without evidence:

1. same syntax
2. same validated vocabulary
3. same resolved semantic identity
4. same platform support

The experiment should determine which of these identities a downstream consumer actually needs.

## Design investigation

Before implementing an executable harness, inspect the current Runtime Conditions spec and tooling and answer the following.

### A. What semantic ownership exists today?

For a validated Condition, identify exactly what current RC semantics and tooling can tell us about:

- the extension owning the Condition `kind`
- the extension owning `interface.type`
- the extension or schema defining interface fields used by `rc-pade`
- the schemas actually applied during validation
- explicit vs fallback kind resolution

For each semantic element, record:

| Semantic element | Spec ownership rule | Current resolver behavior | Identity exposed? | Remaining ambiguity |
|---|---|---|---|---|
| Condition kind | TBD | TBD | TBD | TBD |
| interface.type | TBD | TBD | TBD | TBD |
| interface fields | TBD | TBD | TBD | TBD |
| field values | TBD | TBD | TBD | TBD |
| schemas applied | TBD | TBD | TBD | TBD |

Do not infer ownership that the resolver does not explicitly expose.

### B. Can ownership diverge within one Profile?

Determine whether a legal Profile can have, for example:

```text
kind owner           = Extension A
interface.type owner = Extension B
schema semantics     = Extension B
```

If the spec forbids this, identify the exact rule.

If the current resolver prevents it, identify how.

If the resolver permits something the spec forbids, record an implementation gap rather than treating it as architecture.

### C. Can semantic substitution happen across Profiles?

Determine whether two independently valid Profiles can legally use the same:

```text
kind + interface.type + field shape
```

while resolving that vocabulary from different immutable extension IDs.

If yes, determine whether:

- the two extensions can assign different semantics to the same apparent vocabulary
- current `rc-pade` would distinguish them
- current upstream resolver output gives a platform enough identity to distinguish them before projection

If no, identify the RC invariant that makes substitution impossible.

This is the likely core falsification case for 010.

### D. What exactly does `conditions[].extension` select?

Do not assume that selecting the extension defining a Condition `kind` selects all semantics inside the Condition.

Determine from the current spec:

- the exact scope of `conditions[].extension`
- what vocabulary remains independently resolved
- whether selector choice affects interface type resolution or schema application
- what explicit vs fallback provenance means downstream

Also compare this to current resolver behavior and first-party extension schemas.

### E. What would a platform support contract key on?

Only after A–D are understood, evaluate whether a platform capability catalog would need to key support on:

- `kind + interfaceType`
- resolved extension ID
- extension ID + vocabulary element
- a resolved semantic tuple
- something else

Do not add such a catalog in this experiment until a real falsification case demonstrates the need.

## Questions for the Runtime Conditions group

Before implementing identity-aware projection, get clarification on these if the current spec does not answer them unambiguously:

1. When `conditions[].extension` selects the extension defining `kind`, is that selector intentionally limited to kind ownership, or is it expected to scope other Condition vocabulary too?
2. After validation, is there a canonical resolved semantic identity that downstream consumers are expected to use when declaring platform support?
3. Should two different immutable extension IDs that happen to define the same `kind + interface.type` names be treated as distinct semantic contracts by downstream consumers?
4. If extension artifacts are no longer needed after validation, what stable contract is an adapter expected to be coded against?

Relevant architecture discussion:

https://github.com/orgs/runtimeconditions/discussions/1

## Implementation guardrails

Until the semantic questions above are resolved, Experiment 010 must not:

- add extension identity to `ProjectionPolicy`
- add identity-aware dispatch to the projector
- add a general capability catalog
- change production `rc-pade` parsing
- invent a normalized validated-Profile format
- add validation attestation
- duplicate Runtime Conditions resolution in `rc-pade`
- treat current resolver quirks as intended spec semantics
- begin resource binding or fulfillment work

Production code changes should remain **zero** during the design phase.

## Likely experiment shape

If the RC semantics support the cross-Profile substitution question, the eventual executable experiment should remain small:

```text
Profile A + Extension A ──validate──┐
                                   ├── compare resolved semantics
Profile B + Extension B ──validate──┘
                                   ↓
                            unchanged rc-pade
                                   ↓
                         compare projection result
```

A useful result could be either:

- **substitution is impossible by spec** → document the invariant; no identity gate needed for this reason
- **substitution is possible and semantically distinct** → demonstrate unchanged `rc-pade` cannot distinguish it, then design the smallest downstream support gate
- **current tooling cannot faithfully expose the semantics needed to test it** → stop and report the upstream gap

## Stop conditions

Stop instead of growing architecture if:

- the proposed fixture would be invalid under the current RC spec
- the only way to construct the case is to depend on a known resolver bug
- current tooling reports kind identity but cannot identify the semantics actually used for interface/schema validation
- testing explicit selectors is blocked by first-party schemas rejecting the core selector field
- a result would require assuming unresolved RC-group intent
- implementation would require production `rc-pade` changes before the semantic question is answered

Any of those is a valid Experiment 010 finding.

## Success criteria for the design phase

The design phase is complete when we can state, with evidence:

1. what semantic identity RC defines for each relevant vocabulary element
2. whether same-shaped vocabulary from different extension IDs can be semantically distinct
3. whether current tooling exposes enough resolved identity to enforce platform support safely
4. the smallest falsifiable executable test, if one is possible
5. which remaining questions require upstream clarification

Only then should Experiment 010 gain an executable harness.
