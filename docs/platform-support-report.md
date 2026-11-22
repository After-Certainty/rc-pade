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

## CLI

Optional `--support-report PATH` on `generate` and `bind` writes the report.
Omitted, CLI behavior matches prior releases aside from the new policy field.
On `bind`, the report is written even when projection fails, after empty
bindings revocation.
