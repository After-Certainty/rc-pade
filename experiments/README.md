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
| 006 | [`006-rc-demos-dev-container`](006-rc-demos-dev-container/) | Composed rc-demos Profile + `outsidePADE` classification; source_control fails on operations model |
| 007 | [`007-s3-fulfillment`](007-s3-fulfillment/) | **Baseline only:** S3 `aws.s3.bucket.write` path prepared; live AWS fulfillment not done |
| 008 | [`008-rc-field-projection`](008-rc-field-projection/) | Opaque interface fields + bounded matcher project live `source_control`/`git` → `github.repo.read` + `github.repo.write` |

```text
001  Minimal RC profile → DevelopmentSession
002  Real upstream RC S3 profile
003  Source → RC profiler → rc-pade
004  Same flow in Coder
005A Local Coder identity investigation
005B GCE workload identity proof
005C Deployed PADE multi-issuer fulfillment proof
006  Composed rc-demos Profile → rc-pade (outsidePADE vs source_control operations mismatch)
007  S3 fulfillment baseline (generation + validate/plan; not live S3)
008  Opaque fields + bounded matcher project source_control/git → GitHub capability intent
```

**005C** closes the identity/fulfillment substrate for the GCE-backed Coder workspace.

**006** feeds a real composed rc-demos `RuntimeConditionsProfile` into `rc-pade` without inventing a fixture. After a minimal `outsidePADE` policy distinction, HTTP and Google Analytics are explicitly out of scope; `source_control`/`git` fails because the projector still requires `operations[].name`.

**007** preserves the earlier AWS S3 fulfillment baseline (originally numbered 006). Live S3, AWS setup, federation, and broker AWS fulfillment remain unfinished.

**008** preserves opaque extension interface fields and adds a bounded `require` / `project` / `cover` matcher. The same composed Profile now emits `github.repo.read` and `github.repo.write` under provisional Reading 1 policy, while HTTP/Analytics stay `outsidePADE` and legacy S3 `operations` projection remains.
