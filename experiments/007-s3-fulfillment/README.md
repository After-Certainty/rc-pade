# Experiment 007 — S3 fulfillment

**Status: DONE — baseline preparation + AWS bootstrap (Phase 1) + direct GCE → AWS federation proof (Phase 2) + broker-side AWS fulfillment (Phase 3).**

The broker AWS fulfillment phase (see [Phase 3](#phase-3--gce-caller--deployed-pade-broker--aws-s3-putobject)) proves, live from the GCE-backed Coder workspace, that the deployed PADE broker authorizes `aws.s3.bucket.write` for the GCE caller and delivers temporary AWS Material, derived from the broker's own Cloud Run runtime identity, only to the `pade exec` child.

The AWS bootstrap phase (see [AWS bootstrap phase](#aws-bootstrap-phase)) adds operator-side scripts that prepare AWS for a later federation test. It does not exercise federation or write to S3.

The GCE → AWS federation phase (see [Phase 2](#phase-2--gce-workload-identity--aws-sts--s3-putobject)) proves, live from the GCE-backed Coder workspace, that the GCE workload identity federates directly to the Phase 1 role and exercises exactly the narrow S3 authority the workload needs. No PADE broker is involved; broker-side AWS fulfillment is Phase 3.

The baseline section below prepares the RC → rc-pade → generated `DevelopmentSession` → PADE validate/plan baseline. On its own the baseline does **not** claim live S3 access, AWS provisioning, Google→AWS federation, or broker-side AWS fulfillment. Those are covered by Phases 1–3.

## Question

Can the existing documented source → Runtime Conditions profiler → rc-pade → PADE validate/plan chain still produce and accept `aws.s3.bucket.write` intent for the discovered `PutObject` operation, so a later step can fulfill that capability against real S3?

## Sequence context

| Experiment | Proved |
|------------|--------|
| [003](../003-source-to-session/) | Ordinary boto3 source → RC profiler → rc-pade → session |
| [004](../004-coder-workspace/) | Same chain + PADE validate/plan inside Coder |
| [005C](../005c-deployed-pade/) | Deployed multi-issuer broker fulfills `github.repo.read` for GCE identity |
| **007 baseline (this)** | Re-confirmed S3 session generation + validate/plan; remaining AWS work deferred |
| **007 AWS bootstrap (this)** | Reproducible operator-side S3 bucket + narrow Google web-identity IAM role; federation deferred to the next PR |
| **007 GCE → AWS federation (this)** | GCE metadata identity → STS `AssumeRoleWithWebIdentity` → temporary credentials → ordinary boto3 `PutObject`; wrong audience, outside-prefix write, and `ListObjectsV2` rejected |
| **007 broker AWS fulfillment (this)** | GCE caller → deployed PADE broker → `aws.s3.bucket.write` → Cloud Run runtime identity → STS → temporary Material in `pade exec` child → ordinary boto3 `PutObject`; outside-prefix write, `ListObjectsV2`, and GCE `google-analytics.read` denied |

## Commands run

### Original baseline (PADE v0.2.1)

From repository root (originally on branch `experiment/006-s3-fulfillment`; evidence preserved after renumbering to 007):

```sh
bash experiments/004-coder-workspace/run.sh
mise run test
mise run check-demo
```

`run.sh` reuses Experiment 003’s profiler path and projects with `examples/s3-put-object/policy.yaml`, then runs PADE `validate` and `plan` against the generated session (documented Experiment 004 workflow, PADE **v0.2.1**). The generated session was not manually edited.

### Follow-up check (PADE v0.3.0)

Against the **same** generated file from the successful baseline run (no regenerate, no manual edit):

```sh
/tmp/pade-deployed-gce-8V1f9j/pade -v
/tmp/pade-deployed-gce-8V1f9j/pade validate -f experiments/004-coder-workspace/generated/development-session.yaml
/tmp/pade-deployed-gce-8V1f9j/pade plan -f experiments/004-coder-workspace/generated/development-session.yaml
```

Results:

```text
pade version v0.3.0 (0467ed2, built 2026-09-13T02:26:11Z)

✓ development-session.yaml DevelopmentSession/aws-s3-direct-client is valid
✓ capability "aws.s3.bucket.write" is well formed
Manifest OK.

aws.s3.bucket.write
  access: write
  provider: (unbound)
  bound: false
  required: true
  status: unbound
  message: no local binding configured
```

Session still matches `experiments/002-real-rc-profile/expected-pade.yaml`.

## Source workload and mapping policy

| Input | Value |
|-------|--------|
| Source | Ordinary boto3 direct-client `PutObject` (`experiments/003-source-to-session/app/storage.py`, byte-identical to pinned upstream fixture) |
| Mapping policy | `examples/s3-put-object/policy.yaml` (`PutObject` → `aws.s3.bucket.write`) |
| Expected golden session | `experiments/002-real-rc-profile/expected-pade.yaml` |

## Generated session (reproducible artifact)

Gitignored outputs from this baseline run (reproduce with `bash experiments/004-coder-workspace/run.sh`):

- `experiments/004-coder-workspace/generated/runtime-conditions.yaml` — includes `PutObject`
- `experiments/004-coder-workspace/generated/development-session.yaml` — requests `aws.s3.bucket.write`
- `experiments/004-coder-workspace/generated/pade-plan.txt` — unbound `aws.s3.bucket.write` (expected)
- `experiments/004-coder-workspace/generated/environment.txt` — toolchain / pin summary

Committed golden equivalent: `experiments/002-real-rc-profile/expected-pade.yaml`.

## Versions recorded

| Component | Version |
|-----------|---------|
| rc-pade (this branch HEAD at run) | `10cc1867a884736fb7a140e867755702d16c76a8` |
| Runtime Conditions sdk-authorship-discovery | `2b54b1230afc6075986b888701ef1b5c91c9ec4b` |
| Runtime Conditions extensions | `e4c228ebab54c294783059772e973a665fc5f3f5` |
| Runtime Conditions python-rc-profiler | `3c882dbc7427f4c13bd127bc13069e11fc548e67` |
| PADE original baseline validate/plan (004 documented path) | **v0.2.1** / `d50174a2696743db3879dc98615801f5ad8d462a` |
| PADE follow-up check (temporary binary; same session) | **v0.3.0** / `0467ed2` |
| PADE used in Experiment 005C (deployed fulfillment) | **v0.3.0** / `0467ed2` |

### PADE version comparison (historical pins preserved)

- **Original baseline** used Experiment 004’s pin **v0.2.1** (`d50174a`). That remains the recorded generation-chain validate/plan path.
- **Follow-up check** used the temporary binary `/tmp/pade-deployed-gce-8V1f9j/pade` at **v0.3.0** (`0467ed2`, same as 005C) against the unchanged generated session. Both validate and plan succeeded with unbound `aws.s3.bucket.write`.
- Historical 003/004/005C provenance was left unchanged.
- **Other local binary:** `/home/ksteffe/pade-005c/bin/pade` reports `pade version dev (7354254, …)` — not used.
- `pade` was not on `PATH` for these runs; 004 clones v0.2.1 into `.work/`; the v0.3.0 check used the temporary binary path above.

## What passed

- Source → RC profiler → rc-pade → generated session matched Experiment 002 golden `DevelopmentSession`.
- Generated RC profile contains `PutObject`; generated session requests `aws.s3.bucket.write`.
- PADE **v0.2.1** `validate` and `plan` succeeded; plan shows unbound `aws.s3.bucket.write` (side-effect-free; expected for this stage).
- PADE **v0.3.0** follow-up `validate` and `plan` against the same generated session also succeeded; `aws.s3.bucket.write` remains present and unbound.
- `mise run test` passed.
- `mise run check-demo` passed.

## Blockers / non-goals for this baseline

None for generation/validate/plan. The following were **intentionally not** attempted:

- AWS bucket or role creation
- IAM configuration or AWS access keys
- Google → AWS federation
- Broker-side AWS / S3 fulfillment
- Live S3 `PutObject` execution
- Changing the deployed PADE broker

Host note: `python3-venv` was required for the documented Experiment 003/004 scripts and was installed on this workspace before re-running the chain.

## Remaining work (Experiment 007 completion)

```text
AWS bucket + role setup
      ↓
Google → AWS federation for the GCE workload identity
      ↓
broker-side AWS fulfillment for aws.s3.bucket.write
      ↓
live S3 execution via ordinary application code
```

Progress: "AWS bucket + role setup" is done (Phase 1, PR #13). "Google → AWS federation for the GCE workload identity" and live `PutObject` via ordinary application code are proven directly, without the broker (Phase 2, PR #14). "Broker-side AWS fulfillment", with live `PutObject` via ordinary application code consuming broker-delivered Material, is done (Phase 3). All four steps are complete.

005C already validated GCE identity against the deployed multi-issuer broker for `github.repo.read`. Completing 007 should reuse that identity substrate and extend fulfillment to S3—not re-prove GCE metadata identity.

## AWS bootstrap phase

**Completing this phase does not complete Experiment 007.** It makes the first step of the remaining work ("AWS bucket + role setup") reproducible from an operator workstation.

```text
Phase 1 — local/operator bootstrap (this phase)

developer workstation
    ↓
AWS administrator credentials
    ↓
S3 bucket + narrow IAM role/trust
    ↓
AWS ready for federation testing

Phase 2 — deferred to next PR

GCE workload identity
    ↓
AWS STS AssumeRoleWithWebIdentity
    ↓
temporary AWS credentials
    ↓
live PutObject
```

Scripts live in [`scripts/`](scripts/); `mise.toml` only wraps them.

| Task | Script | Effect |
|------|--------|--------|
| `mise run 007:check-aws` | `check-aws.sh` | Read-only preflight: CLI, caller identity, region, inputs, existing resources |
| `mise run 007:bootstrap-aws` | `bootstrap-aws.sh` | **Mutates AWS.** Creates/reconciles bucket, role, inline policy; fails closed |
| `mise run 007:show-aws` | `show-aws.sh` | Read-only summary; writes gitignored `generated/aws-bootstrap.json` |
| `mise run 007:teardown-aws` | `teardown-aws.sh` | **Mutates AWS.** Conservative, tag-checked teardown with typed confirmation |
| `mise run 007:test-scripts` | `test-local.sh` | Offline checks (syntax, shellcheck if present, policy shape, fail-closed inputs); no AWS calls |

### Configuration

| Variable | Required | Meaning |
|----------|----------|---------|
| `AWS_REGION` | yes (falls back to `AWS_DEFAULT_REGION`, then `aws configure get region`) | Region for the bucket |
| `RC_PADE_007_BUCKET` | yes, no default | Globally unique bucket name, chosen explicitly by the operator |
| `RC_PADE_007_ROLE_NAME` | no (default `pade-experiment-007-s3-write`) | IAM role name |
| `RC_PADE_007_GOOGLE_SUB` | yes for bootstrap | Numeric unique ID of the GCE-attached service account (the ID token `sub`) |
| `RC_PADE_007_AUDIENCE` | yes for bootstrap | Exact audience the GCE workload will request from the metadata identity endpoint |

The AWS account ID is always derived from `aws sts get-caller-identity`; it is never configured or committed. The Google subject and audience are identifiers, not credentials, but bootstrap refuses to guess them and refuses to build a trust policy without them.

The service-account unique ID can be read by an operator with, for example, `gcloud iam service-accounts describe <sa-email> --format='value(uniqueId)'`, or from the `sub` claim recorded by [005B](../005b-gcp-workload-identity/)'s `inspect.sh`.

### Local workflow

Requires AWS CLI v2 and `jq`, authenticated with credentials allowed to manage S3 buckets and IAM roles.

```sh
export AWS_REGION=<region>
export RC_PADE_007_BUCKET=<globally-unique-bucket-name>
export RC_PADE_007_ROLE_NAME=pade-experiment-007-s3-write
export RC_PADE_007_GOOGLE_SUB=<numeric-service-account-unique-id>
export RC_PADE_007_AUDIENCE=<exact-audience-phase-2-will-request>

mise run 007:check-aws
mise run 007:bootstrap-aws
mise run 007:show-aws
```

Bootstrap prints the account, region, bucket, role, S3 scope, Google subject, audience, and both rendered policies, then asks for confirmation before mutating anything.

Teardown:

```sh
mise run 007:teardown-aws
```

### Resources and exact authority

Bootstrap creates or reconciles only:

1. **S3 bucket** `$RC_PADE_007_BUCKET` in `$AWS_REGION`, tagged `Project=rc-pade`, `Experiment=007`, `Purpose=s3-federation`, with all four public-access-block settings enabled. Encryption (SSE-S3) and object ownership (BucketOwnerEnforced) use the AWS defaults and are reported by `show-aws`.
2. **IAM role** `$RC_PADE_007_ROLE_NAME` with the same tags, max session 3600s, and this trust policy:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "accounts.google.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": { "StringEquals": {
         "accounts.google.com:aud": "<RC_PADE_007_GOOGLE_SUB>",
         "accounts.google.com:oaud": "<RC_PADE_007_AUDIENCE>",
         "accounts.google.com:sub": "<RC_PADE_007_GOOGLE_SUB>"
       }}
     }]
   }
   ```

3. **Inline role policy** `experiment-007-s3-put-object`:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "s3:PutObject",
       "Resource": "arn:aws:s3:::<RC_PADE_007_BUCKET>/experiment-007/*"
     }]
   }
   ```

No `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`, or wildcard actions are granted. No IAM OIDC provider, IAM user, or access key is created; `accounts.google.com` is AWS's built-in Google web-identity principal.

### Google trust semantics (`aud` vs `azp`)

AWS maps Google ID token claims to condition keys as follows ([IAM condition context keys, OIDC "Default" mapping](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html)):

| AWS condition key | Google ID token claim |
|-------------------|-----------------------|
| `accounts.google.com:aud` | `azp` when present, otherwise `aud` |
| `accounts.google.com:oaud` | `aud` |
| `accounts.google.com:sub` | `sub` |

GCE metadata identity tokens set `azp` to the attached service account's unique ID, the same value as `sub` ([Compute Engine: verifying instance identity](https://cloud.google.com/compute/docs/instances/verifying-instance-identity)). So for this workload:

- the requested audience is enforced by **`oaud`**, not `aud`;
- `accounts.google.com:aud` is pinned to the service-account unique ID (the `azp` value);
- `sub` is pinned to the same ID.

Pinning `accounts.google.com:aud` to the requested audience would make every GCE token fail the trust check. Dropping the audience condition entirely would let any audience minted for this service account assume the role. The policy above avoids both. Phase 2 must confirm on a live token that `azp == sub` (005B collected `azp` but did not record it).

### Fail-closed behavior

Bootstrap stops before mutation when inputs are missing or invalid (non-numeric subject, audience with whitespace or wildcards, invalid bucket or role name), and stops without changing anything when:

- caller identity cannot be established;
- the bucket exists but belongs to another account or is inaccessible (`--expected-bucket-owner`);
- the bucket exists in this account but lacks the Experiment 007 tags, or is in a different region;
- the role exists but lacks the Experiment 007 tags;
- the role exists with a different trust policy (the diff is printed; teardown and re-bootstrap if the change is intended);
- the role has attached managed policies or any inline policy other than `experiment-007-s3-put-object`.

Teardown additionally:

- touches only resources with the exact configured names, in the caller's account, carrying all three tags;
- deletes only objects under `experiment-007/` and never unrelated objects;
- keeps the bucket if unrelated objects remain or versioning was ever enabled;
- refuses to delete a role that has other policies attached;
- prints the full removal plan and requires typing the role name.

Tags are a secondary safety check; exact names and account ownership are always checked too.

### Safety invariants

- No AWS access keys are created.
- No static workload credentials are committed.
- No Google ID tokens are minted and no GCE metadata is queried.
- No STS web-identity exchange occurs; no federated S3 `PutObject` is performed.
- No PADE, broker, or production rc-pade changes.
- Resource identity stays operator/platform configuration, not Runtime Conditions intent.
- The role's authority is exactly `s3:PutObject` on `experiment-007/*` in one bucket.
- CI (`.github/workflows/experiment-007.yml`) runs only offline checks and uses no AWS credentials.

### Evidence to capture after bootstrap

- `mise run 007:check-aws` output (before and after bootstrap).
- `mise run 007:bootstrap-aws` output, including the printed plan and final role ARN.
- `mise run 007:show-aws` output and the gitignored `generated/aws-bootstrap.json`, with `checks.trustPolicyMatchesConfig: true` and `checks.permissionsPolicyMatchesExpected: true`.
- The rc-pade commit used (recorded in the JSON).

Redact the AWS account ID before publishing evidence outside the team, and follow 005C's practice of not publishing the numeric Google `sub` in public docs.

### Bootstrap run (recorded)

Operator run from a developer workstation on 2026-09-30 (UTC) with `check-aws`, `bootstrap-aws`, then `show-aws`, at rc-pade commit `809ebdff95c8aaef6403ecf03c2b8f71cb80f16c`. Summary from the gitignored `generated/aws-bootstrap.json` (account ID redacted, numeric subject omitted):

| Fact | Observation |
|------|-------------|
| Region | `us-east-1` |
| Bucket | `after-certainty-rc-pade-007-1abcdf`, owned by the caller account |
| Bucket tags | `Project=rc-pade`, `Experiment=007`, `Purpose=s3-federation` |
| Public access block | all four settings `true` |
| Encryption / ownership / versioning | SSE-S3 (`AES256`) / `BucketOwnerEnforced` / unversioned |
| Role | `arn:aws:iam::<account>:role/pade-experiment-007-s3-write`, same tags, max session 3600s |
| Trust principal / action | `accounts.google.com` / `sts:AssumeRoleWithWebIdentity` |
| Trust conditions (`StringEquals`) | `accounts.google.com:aud` = service-account unique ID; `accounts.google.com:sub` = same ID; `accounts.google.com:oaud` = `https://rc-pade-007.after-certainty.aws` |
| Service account | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` (subject from 005B) |
| Permissions | inline `experiment-007-s3-put-object` only: `s3:PutObject` on `arn:aws:s3:::after-certainty-rc-pade-007-1abcdf/experiment-007/*`; no attached managed policies |
| `trustPolicyMatchesConfig` | `true` |
| `permissionsPolicyMatchesExpected` | `true` |

Not done in this run: no access keys created, no Google token minted, no STS web-identity exchange, no object written. The caller was the account root user via `aws login`; Phase 2 and later operator work should use a non-root IAM principal.

### Remaining for Phase 2 (next PR)

From the GCE-backed Coder workspace:

1. Mint a GCE metadata ID token for exactly `RC_PADE_007_AUDIENCE` (raw JWT never printed) and confirm `iss`, `aud`, `sub`, and `azp == sub`.
2. Call `aws sts assume-role-with-web-identity` against the role ARN.
3. Handle the temporary credentials in-process only; never print or persist them.
4. `PutObject` under `experiment-007/` and record the safe result.
5. Negative checks: writes outside `experiment-007/` and non-`PutObject` actions are denied; a token for a different audience is rejected.
6. Then continue with broker-side AWS fulfillment for `aws.s3.bucket.write`, as listed in [Remaining work](#remaining-work-experiment-007-completion).

Items 1–5 are done in [Phase 2](#phase-2--gce-workload-identity--aws-sts--s3-putobject). Item 6 is Phase 3.

## Phase 2 — GCE workload identity → AWS STS → S3 PutObject

**Completing this phase does not complete Experiment 007.** It isolates and proves one substrate layer, with no PADE broker involved.

```text
Phase 1
operator workstation
    ↓
AWS bucket + role bootstrap
DONE — PR #13

Phase 2
GCE workload identity
    ↓
AWS STS AssumeRoleWithWebIdentity
    ↓
temporary credentials
    ↓
ordinary boto3 PutObject
DONE — PR #14

Phase 3
GCE workload identity
    ↓
PADE broker
    ↓
aws.s3.bucket.write provider
    ↓
AWS STS
    ↓
ordinary application
DONE — see Phase 3 below (provider in pade-broker-deployment)
```

### Question

Can the existing GCE-backed Coder workload identity assume the narrow Phase 1 role using `AssumeRoleWithWebIdentity`, obtain temporary AWS credentials, and use them to execute the ordinary S3 `PutObject` workload that Runtime Conditions discovered earlier?

### What this phase proves

Google/GCE workload identity can directly federate to AWS and exercise the exact narrow S3 authority required by the Experiment 007 workload: `s3:PutObject` under `experiment-007/` succeeds, and a wrong audience, a write outside the prefix, and a non-`PutObject` S3 action are all rejected.

### What this phase does not prove

- broker-side AWS fulfillment;
- PADE resolution of `aws.s3.bucket.write`;
- a full RC → rc-pade → broker → S3 vertical slice;
- generic AWS support in PADE;
- generic cloud federation support in Runtime Conditions.

### Tasks

Scripts live in [`scripts/`](scripts/); `mise.toml` only wraps them.

| Task | Script | Effect |
|------|--------|--------|
| `mise run 007:check-gce-aws` | `check-gce-aws.sh` → `gce_aws.py check` | Refuses ambient AWS credentials; validates config; checks GCE metadata and the attached service account; mints one metadata ID token for `RC_PADE_007_AUDIENCE` and inspects safe claims; checks `RC_PADE_007_ROLE_ARN` syntax. **No STS or S3 calls.** Writes gitignored `generated/gce-aws-check.json` |
| `mise run 007:test-gce-aws` | `test-gce-aws.sh` → `gce_aws.py test` | Live experiment in one process: identity checks, STS exchange, caller-identity confirmation, ordinary `storage.upload` PutObject, three negative checks. Writes gitignored `generated/gce-aws-federation.json` |
| `mise run 007:test-scripts` | `test-local.sh` (+ `test_gce_aws.py`) | Offline only: syntax, shellcheck if present, static safety guards, unit tests, wrapper refusals |

### Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `AWS_REGION` | `us-east-1` | STS/S3 region (`aws configure` and profiles are never consulted) |
| `RC_PADE_007_BUCKET` | `after-certainty-rc-pade-007-1abcdf` | Phase 1 bucket |
| `RC_PADE_007_AUDIENCE` | `https://rc-pade-007.after-certainty.aws` | Exact audience requested from GCE metadata and pinned by the trust policy's `oaud` |
| `RC_PADE_007_ROLE_ARN` | **none — required** | `arn:aws:iam::<account>:role/pade-experiment-007-s3-write`, supplied to the workspace by the operator. Never guessed, never committed |

If `RC_PADE_007_ROLE_ARN` is missing, `007:test-gce-aws` stops before any metadata, STS, or S3 call with `RC_PADE_007_ROLE_ARN must be supplied`.

```sh
export RC_PADE_007_ROLE_ARN=arn:aws:iam::<account>:role/pade-experiment-007-s3-write
mise run 007:check-gce-aws
mise run 007:test-gce-aws
```

`007:test-gce-aws` creates a gitignored venv at `.work/experiment-007-gce-aws/venv` with the boto3/botocore/s3transfer versions already pinned in this experiment's provenance.

### How authority is isolated

- **Ambient credentials refused.** Both wrappers and the Python harness refuse to run if `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_SECURITY_TOKEN`, or `AWS_PROFILE` is present (names reported, values never read or printed).
- **No fallback.** Before the exchange the harness points `AWS_CONFIG_FILE` / `AWS_SHARED_CREDENTIALS_FILE` at `/dev/null`, disables the EC2 metadata provider, removes web-identity/container provider variables, and asserts that boto3's default chain resolves **no** credentials.
- **Token in memory only.** The Google ID token is fetched in-process from `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity` (`Metadata-Flavor: Google`, `format=full`, no proxy). It is never printed, logged, written to disk, placed in argv or a shell variable, or included in errors. No `aws` CLI is used.
- **Unsigned STS call.** `AssumeRoleWithWebIdentity` is made with a botocore client using `signature_version=UNSIGNED`, so no pre-existing AWS credentials exist or are needed. Session duration is 900s.
- **Ordinary chain for the workload.** The temporary credentials are placed only in the harness process's environment (boto3's standard environment provider; recorded `workloadCredentialSource: env`). The unmodified [`experiments/003-source-to-session/app/storage.py`](../003-source-to-session/app/storage.py) `upload()` then calls `boto3.client("s3").put_object(...)`. No subprocess is started after the credentials exist; they are removed from the environment before exit and never written anywhere.
- **Claims are inspected, not verified.** Locally decoded JWT claims are inspection only. AWS STS accepting the correct-audience token (and rejecting the wrong-audience one) is the verification evidence.

### Live run (recorded)

Run from the GCE-backed Coder workspace on 2026-09-30 (UTC) at rc-pade commit `c625114173da74cda99c6033b0bd1cb462130932` (clean worktree), with only `RC_PADE_007_ROLE_ARN` supplied. Summary from gitignored `generated/gce-aws-federation.json` (account ID redacted; numeric Google subject never recorded):

| Fact | Observation |
|------|-------------|
| Ambient AWS credential variables | none; `~/.aws` absent; boto3 default chain resolved no credentials before STS |
| GCE environment | metadata reachable, `Metadata-Flavor: Google`; project `after-certainty`, zone `us-central1-a` |
| Attached service account | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` (matches expected) |
| Token `iss` | `https://accounts.google.com` |
| Token `aud` | `https://rc-pade-007.after-certainty.aws` (matches configured) |
| `sub` / `azp` | both present; **`azp == sub`: true** (values not recorded) |
| Token `email` claim | expected service account; lifetime 3600s |
| STS `AssumeRoleWithWebIdentity` | **accepted**; provider `accounts.google.com`; STS subject matches token `sub` |
| Assumed role | `arn:aws:sts::<account>:assumed-role/pade-experiment-007-s3-write/rc-pade-007-gce-20260930T031703Z` |
| Credential expiration | `2026-09-30T03:32:03Z` (900s session) |
| `GetCallerIdentity` with temporary credentials | same assumed-role ARN; credential source `env` |
| Positive `PutObject` (`storage.upload`) | **succeeded**: `s3://after-certainty-rc-pade-007-1abcdf/experiment-007/gce-federation-proof.txt`, ETag `"91fce052dd1a8ce9fbdf16b0bc8a270d"` |
| A. Wrong audience `https://rc-pade-007-wrong-audience.after-certainty.aws` | **rejected** by STS (`AccessDenied`) |
| B. `PutObject` `experiment-007-negative/should-not-write.txt` | **denied** (`AccessDenied`) |
| C. `ListObjectsV2` on `experiment-007/` | **denied** (`AccessDenied`) |
| Result | **passed** |

An earlier identical run at commit `1ba4f7c` also passed; the harness was then changed only to avoid leaving `__pycache__/` in Experiment 003's app directory, and the run above was repeated to record final evidence.

The proof object remains in the bucket for operator inspection; the role has no `GetObject`/`DeleteObject`, and `007:teardown-aws` removes objects under `experiment-007/`. No IAM permissions or trust policy were changed.

### Safety invariants observed

- No AWS IAM users, access keys, `aws login`, AWS profiles, or durable AWS credentials in the workspace.
- No raw Google token in logs, output, evidence, files, argv, or shell tracing (`set -x` is never enabled; offline guards enforce it).
- No AWS temporary credentials logged or persisted; `~/.aws/credentials` never written.
- Generated evidence was checked for the account ID, JWT-shaped values, access-key IDs, and the numeric subject before writing and after the run.
- CI runs only `test-local.sh`: no GCE, no token minting, no STS, no S3, no AWS credentials.

### Resource ownership (unchanged)

Runtime Conditions expresses `aws.s3` / `PutObject` demand; rc-pade projects `aws.s3.bucket.write`; the platform/operator owns the concrete bucket, IAM role, trust relationship, and temporary credential derivation. Neither the bucket nor the role appears in the Runtime Conditions Profile.

### Why Phase 2 alone did not complete Experiment 007

Phase 2 has the workload federate to AWS directly. The PADE target is for the **broker** to resolve `aws.s3.bucket.write` for the verified GCE identity and derive the scoped AWS credentials, so the ordinary application receives authority through PADE rather than through a harness. That requires an AWS S3 provider in the deployed broker. The provider was added in [`After-Certainty/pade-broker-deployment`](https://github.com/After-Certainty/pade-broker-deployment) (#14), and the live proof is Phase 3 below.

## Phase 3 — GCE caller → deployed PADE broker → AWS S3 PutObject

```text
GCE/Coder workload identity (caller)
    ↓
PADE consumer (pade exec)
    ↓
deployed PADE broker: verifies + authorizes the GCE caller
    ↓
aws.s3.bucket.write → deployment-owned AWS S3 provider
    ↓
Cloud Run runtime service-account identity
    ↓
Google metadata ID token for the AWS audience
    ↓
AWS STS AssumeRoleWithWebIdentity
    ↓
temporary AWS Material → pade exec child only
    ↓
ordinary boto3 PutObject
DONE
```

### Live result

A real GCE-backed Coder workload requested `aws.s3.bucket.write` through the deployed PADE broker. The broker authorized the caller, the deployment-owned provider federated Cloud Run runtime identity through AWS STS, temporary AWS Material reached only the scoped child, and ordinary boto3 PutObject succeeded while the tested broader S3 operations were denied.

Two identities stay separate. The caller's GCE token authenticates **only** to the broker, with the broker URL as audience. The broker's Cloud Run runtime service account is the identity AWS trusts for the Phase 3 role `pade-broker-experiment-007-s3-write`, which is distinct from the Phase 2 role. The caller token is never presented to AWS.

### What this phase does not prove

- generic AWS support in PADE;
- that Runtime Conditions performs provisioning;
- behavior for other callers (an unauthorized second GCE subject, or Cursor).

### Commands run

From the GCE-backed Coder workspace, with explicit arguments (no `PADE_BINDINGS`):

```sh
pade exec \
  --bindings /tmp/exp007/bindings.yaml \
  -f /tmp/exp007/pade.yaml \
  --capability aws.s3.bucket.write \
  -- /tmp/exp007-venv/bin/python <child script>
```

- **PADE consumer:** `go install github.com/After-Certainty/pade/cmd/pade@v0.3.0` into `/tmp`. `go version -m` reports the module line `github.com/After-Certainty/pade v0.3.0`. `pade --version` reports `dev`, because plain `go install` carries no release ldflags.
- **Bindings:** generated by pade-broker-deployment `scripts/print-agent-bindings-gce.sh` at `efdbe86`, with `PROJECT_ID=after-certainty PROJECT_NUMBER=754719312452`. `make` was not installed, and `gcloud projects describe` is denied to the Coder SA. Each capability uses `provider: broker, identity: gce`, with endpoint and audience set to the broker URL. For the GCE-policy negative test only, one temporary `google-analytics.read` broker entry was added.
- **Manifest:** a temporary `DevelopmentSession` declaring `aws.s3.bucket.write` (write) and `google-analytics.read` (read). The same capability and access appear in the generated session from the baseline, but the live run used the temporary manifest rather than the generated file.
- **Child:** the child used `/tmp/exp007-venv` (boto3 `1.43.105`). The positive test called the unmodified [`experiments/003-source-to-session/app/storage.py`](../003-source-to-session/app/storage.py) `upload()`.
- None of the temporary files were committed, and none contain credentials.

### Live run (recorded)

Run on 2026-09-30, `04:33:25Z`–`04:37:13Z` UTC. The summary below is from the gitignored `generated/broker-fulfillment.json`. No account ID, full role ARN, numeric Google subject, tokens, credentials, or broker log lines are recorded.

| Fact | Observation |
|------|-------------|
| pade-broker-deployment master | `efdbe8627f927440e147dd01b3094ab80e4b0a20` (includes #14) |
| Broker URL | `https://pade-broker-754719312452.us-central1.run.app` |
| Broker PADE (per `versions.env`, not observed live) | `v0.3.0` @ `0467ed22034a7ae6a2e636a63a277bbd25d23263` |
| Ambient AWS credential variables | none of the 8 standard variables; `~/.aws` absent; `boto3.Session().get_credentials() is None` → `True` before PADE |
| Caller | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com`, project `after-certainty`, zone `us-central1-a` |
| Caller token (locally decoded only) | `iss=https://accounts.google.com`; `aud` = broker URL; subject present; temp file mode 600, deleted after inspection |
| Broker resolve `aws.s3.bucket.write` | **authorized**; `Injecting capabilities: aws.s3.bucket.write (broker)` |
| Child Material | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_S3_BUCKET`, `AWS_S3_PREFIX` all present; access key has STS temporary `ASIA` prefix |
| Platform binding (equality-checked in child) | bucket `after-certainty-rc-pade-007-1abcdf`, prefix `experiment-007/`, region `us-east-1` |
| Positive `PutObject` (`storage.upload`) | **succeeded**: `experiment-007/broker-fulfillment-proof.txt`, ETag present |
| A. `PutObject` `experiment-007-negative/should-not-write.txt` | **denied** (`AccessDenied`) |
| B. `ListObjectsV2` on the bucket | **denied** (`AccessDenied`) |
| C. GCE `google-analytics.read` | GCE caller denied `google-analytics.read` by broker policy: `broker resolve denied (http 403)`, and the child did not run. A direct resolve with the same caller identity returned `403 {"error":"not_authorized"}`. PADE v0.3.0 returns this only after token verification succeeds and policy denies. |
| Result | **passed** |

The proof object body contains only a marker line and a UTC timestamp. `deployment_git_sha` was omitted because deployed provenance could not be observed. The object remains in the bucket; `007:teardown-aws` removes objects under `experiment-007/`.

### Checks not performed from the Coder identity

| Check | Result |
|-------|--------|
| Cloud Run provenance (`gcloud run services describe pade-broker --project=after-certainty --region=us-central1`) | `PERMISSION_DENIED` on `run.services.get`. The deployed image, `DEPLOYMENT_GIT_SHA`, `PADE_VERSION`/`PADE_REF`, and runtime SA were not observed live. |
| Broker log secret-leak scan (`gcloud logging read --project=after-certainty`, bounded to the test window) | Broker log secret-leak inspection unavailable from Coder identity (`PERMISSION_DENIED` for all log views). |
| STS exchange / Cloud Run runtime identity | Not observed directly. Inferred from temporary `ASIA` Material returned by the broker, which only the deployment-owned provider can produce. |
| Unauthorized second GCE subject; real Cursor subject requesting `aws.s3.bucket.write` | Not live-tested here. Cursor-not-authorized for AWS remains a static config/CI property in pade-broker-deployment. |

### Safety invariants observed

- No IAM, trust policy, broker, PADE core, or rc-pade code changes, and no redeploy.
- No raw Google token, numeric subject, AWS credential, account ID, or full role ARN printed, recorded, or committed.
- The child printed only booleans and error codes. PADE's output redaction additionally masked Material values.

## Renumbering note

This AWS baseline was originally recorded as Experiment 006. It was moved to Experiment 007 so Experiment 006 could cover composed rc-demos → rc-pade interoperability. Historical evidence (commands, versions, validate/plan results) is preserved; only numbering and directory name changed.

## Boundary

- Generated `DevelopmentSession` remains an untrusted request.
- Unbound `aws.s3.bucket.write` in `pade plan` is success for **baseline preparation**, not fulfillment.
- Do not treat the baseline or Phase 1 sections as proof of live S3 access. Phase 2 proves live S3 `PutObject` through **direct** GCE → AWS federation only, not through PADE fulfillment. Phase 3 proves it through deployed-broker fulfillment for this GCE caller.
