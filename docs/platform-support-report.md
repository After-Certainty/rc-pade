# Local PlatformSupportReport

`PlatformSupportReport` (`rc-pade.local/v1alpha1`) is an **rc-pade** artifact for
operator platform-support matching. It is **not**:

- an upstream Runtime Conditions validation report
- signature / handoff trust evidence
- a PADE broker authorization decision
- provider fulfillment proof

## Semantic matrix

| Input | Behavior |
|-------|----------|
| Invalid RC (required or optional) | Reject **upstream** during RC semantic validation; rc-pade does not weaken that gate |
| Valid required + supported | Project normally (`supported_projected`) |
| Valid optional + supported | Project with `required: false` (`supported_projected`) |
| Valid required + unmatched | Fail closed (`unsupported_required`) |
| Valid optional + unmatched | Fail closed by default (`unsupported_optional`); continue only when ProjectionPolicy sets `onUnsupportedOptional: continue` |
| Explicit `outsidePADE` rule | Accept with no capability (`outside_pade`) |
| Matched rule but require/cover/conflict | Fail closed (`projection_policy_error`) |

Unmatched demand is distinct from projection-policy errors and from broker denial.

## Completeness

`complete: true` means every Condition was evaluated and projection succeeded.
`complete: false` means evaluation stopped early; `conditions` may be only a
prefix of the Profile. Treat incomplete reports as diagnostics, not a full
platform-support evaluation.

## Continuation and explicit reporting

`onUnsupportedOptional: continue` requires callers to observe unsupported
optional outcomes:

- Library: use `ProjectWithSupport` (plain `Project` rejects continue mode).
- CLI: `--support-report` is required when the policy enables continue.
  Successful continuation also emits stderr diagnostics for each skipped
  optional Condition.

## CLI

`--support-report PATH` on `generate` and `bind` writes the report atomically.
Omitted, CLI behavior matches prior releases when continuation is not enabled.
On `bind`, the report is written even when projection fails, after empty
bindings revocation. Artifact paths must not collide (for example
`--support-report` must not equal `--output`), including through symlinked
parent directories.

### Bind path / revoke contract

1. `--output` must be absolute.
2. Pre-write collision check: `--output` **only** versus each trusted input
   (`--verified-profile`, `--policy`, `--broker-binding`), with symlinked parents
   resolved. Input/input collisions are not evaluated here. If `--output`
   collides with an input, bind **refuses without writing** — revoking would
   destroy the input. Existing bindings are left unchanged; the operator must
   fix paths. This is the impossible-to-safely-revoke conflict case.
3. Otherwise bind revokes `--output` to `capabilities: {}`.
4. Required arguments, relative optional outs, and **full all-pairs** artifact
   collisions (inputs, `--support-report`, `--session-out`, `--output`) are
   enforced after revoke. Ordinary failures therefore leave empty bindings.
