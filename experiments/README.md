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
| 007 | [`007-s3-fulfillment`](007-s3-fulfillment/) | **Baseline + AWS bootstrap + direct GCE → AWS federation:** S3 `aws.s3.bucket.write` path prepared; operator bucket + Google web-identity role; GCE identity → STS → ordinary boto3 `PutObject` proven live with negative boundaries; **broker AWS fulfillment (Phase 3):** GCE caller → deployed PADE broker → `aws.s3.bucket.write` → ordinary boto3 `PutObject` proven live — DONE |
| 008 | [`008-rc-field-projection`](008-rc-field-projection/) | Opaque interface fields + bounded matcher project live `source_control`/`git` → `github.repo.read` + `github.repo.write` |
| 009 | [`009-rc-validated-projection`](009-rc-validated-projection/) | Upstream rc-extension-resolver gates the same Profile before unchanged rc-pade; RC-invalid vs platform-unsupported separated |
| 010 | [`010-resolved-semantic-identity`](010-resolved-semantic-identity/) | **Design conclusion:** validated visible vocabulary is the downstream semantic contract; no extension-ID-aware projection justified |

```text
001  Minimal RC profile → DevelopmentSession
002  Real upstream RC S3 profile
003  Source → RC profiler → rc-pade
004  Same flow in Coder
005A Local Coder identity investigation
005B GCE workload identity proof
005C Deployed PADE multi-issuer fulfillment proof
006  Composed rc-demos Profile → rc-pade (outsidePADE vs source_control operations mismatch)
007  S3 fulfillment baseline (generation + validate/plan) + AWS bootstrap + direct GCE → AWS STS → live PutObject + deployed-broker aws.s3.bucket.write → live PutObject
008  Opaque fields + bounded matcher project source_control/git → GitHub capability intent
009  Upstream RC validation gate → identical Profile bytes → unchanged rc-pade (cases A–D)
010  Resolved semantic identity question → visible vocabulary remains contract; no identity-aware projector
```

**005C** closes the identity/fulfillment substrate for the GCE-backed Coder workspace.

**006** feeds a real composed rc-demos `RuntimeConditionsProfile` into `rc-pade` without inventing a fixture. After a minimal `outsidePADE` policy distinction, HTTP and Google Analytics are explicitly out of scope; `source_control`/`git` fails because the projector still requires `operations[].name`.

**007** preserves the earlier AWS S3 fulfillment baseline (originally numbered 006) and adds operator-side AWS bootstrap scripts (`mise run 007:*-aws`) for a tagged bucket and a Google web-identity role limited to `s3:PutObject` on `experiment-007/*`. Phase 2 (`mise run 007:*-gce-aws`) proves, from the GCE-backed Coder workspace and without any durable AWS credentials, that the GCE workload identity can call `AssumeRoleWithWebIdentity` and use the temporary role credentials for the ordinary Experiment 003 boto3 `PutObject`, while a wrong-audience token, an outside-prefix write, and `ListObjectsV2` are all rejected. Phase 3 proves, from the same workspace, that the deployed PADE broker authorizes `aws.s3.bucket.write` for the GCE caller, and that its deployment-owned provider (in `pade-broker-deployment`) federates the broker's Cloud Run runtime identity to AWS STS. Temporary Material reaches only the `pade exec` child, where the same ordinary `PutObject` succeeds. An outside-prefix write, `ListObjectsV2`, and GCE `google-analytics.read` are denied.

**008** preserves opaque extension interface fields and adds a bounded `require` / `project` / `cover` matcher. The same composed Profile now emits `github.repo.read` and `github.repo.write` under provisional Reading 1 policy, while HTTP/Analytics stay `outsidePADE` and legacy S3 `operations` projection remains.

**009** puts the current upstream `rc-extension-resolver` (`91c46bf`, not a full sixth-draft validator) in front of unchanged `rc-pade` as an out-of-process gate. The real composed Profile is accepted and projects as in 008 from byte-identical input (SHA-256 chain); an RC-invalid access value (`admin`) is rejected before rc-pade runs; an RC-valid but policy-unsupported value (`clone`) fails in rc-pade with no session. The remaining semantic-identity question is resolved as a design conclusion in 010.

**010** records the Runtime Conditions maintainer clarification that semantic meaning belongs in the visible Condition vocabulary, with namespacing used when meanings are vendor-specific, platform-specific, experimental, or likely to conflict. Duplicate unnamespaced vocabulary is possible but is an extension-authoring risk, not evidence that downstream adapters should recover hidden meaning from extension IDs. `rc-pade` therefore keeps the 008/009 model: validated visible demand + explicit platform projection policy + fail-closed unsupported values. Production changes: zero.
