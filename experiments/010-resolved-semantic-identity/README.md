# Experiment 010 — resolved semantic identity across the validation boundary

**Status: DONE — design conclusion. No executable harness or production `rc-pade` changes needed.**

## Question

Experiment 009 established that Runtime Conditions resolution/validation can run as an upstream gate before an unchanged `rc-pade`, and that RC semantic validity is distinct from platform capability support.

Experiment 010 asked:

> After a Runtime Conditions Profile has been resolved and validated, is the validated Condition vocabulary itself sufficient for safe downstream platform interpretation, or must resolved extension identity/provenance survive validation so the platform knows which semantic contract it is acting on?

The concrete concern was that `rc-pade` classifies Conditions using visible vocabulary such as `kind + interfaceType` plus bounded field predicates. If two different extension IDs could carry different hidden semantics behind the same apparent vocabulary, an adapter might appear to need extension identity to distinguish them.

## Result

For the current Runtime Conditions design, **do not add extension-identity-aware projection to `rc-pade`**.

The intended semantic contract is the Condition vocabulary itself. Extension identity may be available and a platform may choose to use it for a special case, but it is not intended to carry hidden semantic meaning that downstream consumers must recover after validation.

This conclusion comes from the Runtime Conditions architecture discussion:

https://github.com/orgs/runtimeconditions/discussions/1

In the 2026-09-30 maintainer clarification, Colin Lacy described the intended model as follows:

- extension-defined vocabulary should be namespaced when it is vendor-specific, platform-specific, experimental, or likely to conflict;
- that namespacing applies to `kind`, `interface.type`, Condition/interface field names, and non-shared field values;
- `interface.type` and subsequent fields/values are semantically tied to their `kind`;
- duplicate unnamespaced vocabulary is technically possible, but is considered a risky extension-authoring choice rather than a semantic distinction downstream adapters are expected to recover from extension identity;
- if two vocabularies need different meanings, namespacing the `kind` is the preferred way to express that distinction;
- once a Condition has been validated against the extension vocabulary, the extension artifact itself is not expected to be required for provisioning;
- downstream platforms still own interpretation and support boundaries, and may expose those boundaries as a capabilities catalog.

This does **not** turn a `SHOULD`-level namespacing rule into a `MUST`. It records the intended architecture relevant to `rc-pade`: visible semantic vocabulary is the contract; extension identity is not a substitute for vocabulary that failed to express a semantic distinction.

## What happened to the proposed falsification

The original design scaffold proposed constructing two accepted Profiles with the same apparent:

```text
kind + interface.type + field shape
```

but different extension IDs and different semantics, then showing that unchanged `rc-pade` projected them identically.

That fixture is no longer useful as the next experiment.

The spec can permit poorly namespaced extension vocabulary, so a collision can be constructed. But under the clarified design intent, assigning different hidden meanings to identical visible vocabulary would demonstrate an extension-authoring problem, not a requirement for every downstream adapter to perform identity-aware dispatch.

In other words:

```text
different extension IDs
        +
same visible vocabulary
        +
different hidden meaning

does not imply

extension-ID-aware platform dispatch

it implies

the semantic distinction should have been expressed in the vocabulary
```

An executable harness built around the pathological case would risk turning a discouraged authoring pattern into permanent downstream architecture.

## Boundary after 008–010

Experiments 008–010 now support this model:

```text
extension-defined semantic vocabulary
        ↓
Runtime Conditions resolution + validation
        ↓
validated Profile
        ↓
rc-pade platform projection policy
        ↓
supported capability intent
        ↓
downstream fulfillment
```

Responsibilities stay separate:

| Layer | Responsibility |
|---|---|
| Runtime Conditions extension | Define actionable semantic vocabulary; namespace vocabulary when meanings are not globally shared |
| RC validation/resolution | Establish that the Profile uses vocabulary according to the extension contracts |
| `rc-pade` | Interpret validated visible demand using explicit platform policy; fail closed on unsupported demand |
| Platform/operator | Decide support boundaries, resource binding, identity, credentials, provisioning, scale, compliance, cost, networking, and other environment-specific concerns |

The extension artifact does not need to become part of PADE intent, and concrete resource identity remains downstream platform responsibility.

## Consequence for current projection policy

No production change is justified by Experiment 010.

Keep the current direction established by 008 and 009:

- match on visible semantic vocabulary such as `kind`, `interface.type`, and bounded field/value predicates;
- keep projection policy platform-owned and explicit;
- use `cover`/fail-closed behavior so recognized conditions cannot silently lose unsupported values;
- keep RC validation upstream of projection;
- distinguish RC-valid from platform-supported;
- do not infer concrete resource identity, credentials, provider bindings, or provisioning inputs from extension identity.

A future platform capabilities catalog could make support boundaries easier to inspect, but 010 does not introduce one. If such a catalog is added later, current evidence favors keying it on the semantic vocabulary/capabilities the platform supports rather than on extension IDs by default.

## Explicitly not added

Experiment 010 adds none of the following:

- extension identity in `ProjectionPolicy`;
- identity-aware projector dispatch;
- a normalized validated-Profile format;
- validation attestation;
- duplicate Runtime Conditions resolution inside `rc-pade`;
- a general capability catalog;
- resource binding or fulfillment logic.

Production `rc-pade` changes: **zero**.

## Remaining nuance

This is an architectural conclusion for the current design, not a proof that namespace collisions can never occur.

The spec intentionally leaves room for controlled/private extension ecosystems and therefore does not make all namespacing mandatory. A platform is also free to key on extension ID if it has a concrete reason. What 010 concludes is narrower:

> `rc-pade` has no evidence-based reason today to carry resolved extension identity across the validation boundary merely to defend against different hidden meanings behind otherwise identical vocabulary.

That would solve the wrong problem at the wrong layer.

## Reopen conditions

Reopen the identity question only if new evidence appears, for example:

- a real extension ecosystem produces a valid collision that cannot be made semantically explicit through namespaced vocabulary;
- the Runtime Conditions spec changes to define a canonical resolved semantic identity intended for downstream dispatch;
- a first-party extension requires behavior that cannot be expressed through its visible Condition vocabulary;
- a real platform integration demonstrates that extension identity is necessary for safe interpretation rather than merely convenient metadata.

Until then, no executable Experiment 010 harness is warranted.

## Relationship to the architecture discussion

The clarification also reinforces the broader boundary established across the previous experiments:

- application/Profile expresses demand;
- Runtime Conditions provides portable semantic vocabulary and validation;
- `rc-pade` interprets that demand against platform support policy;
- the downstream platform decides concrete resources and fulfillment.

That is consistent with the earlier discussion that concrete resource identity is a platform responsibility unless the application itself intrinsically names a specific resource.

## Conclusion

Experiment 010 closes as a design result:

> Validated visible Runtime Conditions vocabulary is the intended semantic contract for downstream interpretation. Semantic distinctions should be expressed in that vocabulary, using namespacing where needed. `rc-pade` should not add extension-ID-aware projection unless future concrete evidence demonstrates a need.

No code change follows from this experiment.
