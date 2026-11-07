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
| 011 | [`011-coder-rc-bindings`](011-coder-rc-bindings/) | Fail-closed validated RC → broker-only bindings adapter; live GCE Coder → deployed broker fulfills `github.repo.read` and `aws.s3.bucket.write` through 011-produced bindings |
| 012 | [`012-pade-v041-compatibility`](012-pade-v041-compatibility/) | Credential-free PADE v0.4.1 CLI validates/plans existing RC-to-PADE projections |
| 013 | [`013-coder-durable-rc-inputs`](013-coder-durable-rc-inputs/) | Fresh Coder workspace obtains trusted RC/operator inputs from durable template source and regenerates module-managed PADE bindings without manual staging; live read authorize / write deny preserved |
| 014 | [`014-signed-validation-handoff`](014-signed-validation-handoff/) | Fresh Coder verifies signed upstream RC validation handoff before unchanged rc-pade → 011 bind; live read authorize / write deny preserved |
| 015 | [`015-pade-coder-rc-pade-bind-dogfood`](015-pade-coder-rc-pade-bind-dogfood/) | **Planned:** dogfood signed handoff → verified Profile → optional pade-coder module → current `rc-pade bind` → live PADE broker, removing the active 011/report compatibility seam |

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
011  Validated RC → Coder broker bindings adapter; live github.repo.read + aws.s3.bucket.write via 011 bindings
012  Released PADE v0.4.1 validates and plans the existing S3 projections (no broker)
013  Durable trusted RC/operator inputs → fresh Coder → automatic 011 handoff (no manual staging)
014  Signed upstream validation evidence → verified Coder handoff → unchanged rc-pade/PADE
015  Planned dogfood: verified Profile → pade-coder optional module → rc-pade bind → live PADE broker
```

**005C** closes the identity/fulfillment substrate for the GCE-backed Coder workspace.

**006** feeds a real composed rc-demos `RuntimeConditionsProfile` into `rc-pade` without inventing a fixture. After a minimal `outsidePADE` policy distinction, HTTP and Google Analytics are explicitly out of scope; `source_control`/`git` fails because the projector still requires `operations[].name`.

**007** preserves the earlier AWS S3 fulfillment baseline (originally numbered 006) and adds operator-side AWS bootstrap scripts (`mise run 007:*-aws`) for a tagged bucket and a Google web-identity role limited to `s3:PutObject` on `experiment-007/*`. Phase 2 (`mise run 007:*-gce-aws`) proves, from the GCE-backed Coder workspace and without any durable AWS credentials, that the GCE workload identity can call `AssumeRoleWithWebIdentity` and use the temporary role credentials for the ordinary Experiment 003 boto3 `PutObject`, while a wrong-audience token, an outside-prefix write, and `ListObjectsV2` are all rejected. Phase 3 proves, from the same workspace, that the deployed PADE broker authorizes `aws.s3.bucket.write` for the GCE caller, and that its deployment-owned provider (in `pade-broker-deployment`) federates the broker's Cloud Run runtime identity to AWS STS. Temporary Material reaches only the `pade exec` child, where the same ordinary `PutObject` succeeds. An outside-prefix write, `ListObjectsV2`, and GCE `google-analytics.read` are denied.

**008** preserves opaque extension interface fields and adds a bounded `require` / `project` / `cover` matcher. The same composed Profile now emits `github.repo.read` and `github.repo.write` under provisional Reading 1 policy, while HTTP/Analytics stay `outsidePADE` and legacy S3 `operations` projection remains.

**009** puts the current upstream `rc-extension-resolver` (`91c46bf`, not a full sixth-draft validator) in front of unchanged `rc-pade` as an out-of-process gate. The real composed Profile is accepted and projects as in 008 from byte-identical input (SHA-256 chain); an RC-invalid access value (`admin`) is rejected before rc-pade runs; an RC-valid but policy-unsupported value (`clone`) fails in rc-pade with no session. The remaining semantic-identity question is resolved as a design conclusion in 010.

**010** records the Runtime Conditions maintainer clarification that semantic meaning belongs in the visible Condition vocabulary, with namespacing used when meanings are vendor-specific, platform-specific, experimental, or likely to conflict. Duplicate unnamespaced vocabulary is possible but is an extension-authoring risk, not evidence that downstream adapters should recover hidden meaning from extension IDs. `rc-pade` therefore keeps the 008/009 model: validated visible demand + explicit platform projection policy + fail-closed unsupported values. Production changes: zero.

**011** adds a fail-closed experiment-local adapter that turns validated-shaped RC demand, operator projection policy/allowlist, and a broker-only binding template into PADE Consumer bindings for a Coder workspace. Live from the GCE-backed Coder workspace, bindings produced by that adapter fulfilled `github.repo.read` and `aws.s3.bucket.write` through the deployed broker; `github.repo.write` remained denied for this subject.

**012** provides a new release compatibility baseline: checksum-pinned PADE v0.4.1 validates and plans regenerated examples/002 S3 DevelopmentSessions. It does not rewrite historical experiments or imply broker authorization or live S3 fulfillment.

**013** closes the fresh-home lifecycle gap exposed by 011. A completely fresh GCE-backed Coder workspace obtains trusted Profile/evidence and operator policy inputs from a durable Coder-template source, builds the unchanged 011 adapter from a pinned `rc-pade` revision, and regenerates the real module-managed bindings path without manual restaging. Restart and recreate both succeed; fail-closed failure cases hold; live `github.repo.read` authorize / `github.repo.write` deny is unchanged. Signed validation provenance remains Experiment 014.

**014** adds that stronger trust boundary on top of 013's durable delivery. The Coder consumer verifies a signed `rc-demos` validated-profile-handoff (PR #5) for exact Profile and resolved-extension bytes before the unchanged Experiment 011 project/bind path. Adversarial untrusted-handoff cases fail closed; restart and fresh-home recreate succeed; live `github.repo.read` authorize / `github.repo.write` deny is unchanged. Signature verification, Runtime Conditions validity, platform support, and PADE broker authorization remain separate decisions.

**015** is the planned cross-repository dogfood of the cleanup that followed 014. It reuses the signed handoff trust boundary from 014, but replaces the historical Experiment 011 adapter and validator-specific `validation-report.yaml` in the active Coder path with the merged `pade-coder/modules/rc-pade-bindings` helper and the reusable `rc-pade bind --verified-profile` command. The setup PR records checkpoints only; live provenance will be added interactively during the experiment.
