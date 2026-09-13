# Experiments

Sequential interoperability proofs for Runtime Conditions ↔ PADE via `rc-pade`.

| ID | Directory | One-line result |
|----|-----------|-----------------|
| 001 | [`examples/s3-put-object`](../examples/s3-put-object/) (initial fixture) | Minimal RC profile → PADE `DevelopmentSession` |
| 002 | [`002-real-rc-profile`](002-real-rc-profile/) | Real upstream RC S3 profile projects to the same session intent |
| 003 | [`003-source-to-session`](003-source-to-session/) | Ordinary source → RC profiler → rc-pade → session |
| 004 | [`004-coder-workspace`](004-coder-workspace/) | Same generation/validate/plan flow inside a Coder workspace |
| 005A | [`005-coder-identity-discovery`](005-coder-identity-discovery/) | Local Coder: no suitable PADE workload identity |
| 005B | [`005b-gcp-workload-identity`](005b-gcp-workload-identity/) | GCE metadata provides PADE-fit audience-bound Google identity |
| 005C | [`005c-deployed-pade`](005c-deployed-pade/) | Deployed multi-issuer PADE broker fulfills `github.repo.read` for GCE identity |
| 006 | [`006-s3-fulfillment`](006-s3-fulfillment/) | **Baseline only:** RC → session → PADE validate/plan for `aws.s3.bucket.write` (S3 fulfillment not done) |

```text
001  Minimal RC profile → DevelopmentSession
002  Real upstream RC S3 profile
003  Source → RC profiler → rc-pade
004  Same flow in Coder
005A Local Coder identity investigation
005B GCE workload identity proof
005C Deployed PADE multi-issuer fulfillment proof
006  S3 fulfillment baseline (generation + validate/plan; not live S3)
```

**005C** closes the identity/fulfillment substrate for the GCE-backed Coder workspace. Later experiments can assume that path and focus on RC → rc-pade → generated session → deployed fulfillment without re-proving workload identity.

**006** baseline preparation re-confirms the S3 `PutObject` → `aws.s3.bucket.write` generation and PADE validate/plan path. Live S3, AWS setup, federation, and broker AWS fulfillment remain unfinished.
