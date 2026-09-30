# Experiment 007 — S3 fulfillment (baseline preparation)

**Status: baseline preparation + AWS bootstrap tooling — Experiment 007 is not complete.**

The AWS bootstrap phase (see [AWS bootstrap phase](#aws-bootstrap-phase)) adds operator-side scripts that prepare AWS for a later federation test. It does not exercise federation or write to S3.

This record prepares the RC → rc-pade → generated `DevelopmentSession` → PADE validate/plan baseline for later real S3 fulfillment. It does **not** claim live S3 access, AWS provisioning, Google→AWS federation, or broker-side AWS fulfillment.

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

## Renumbering note

This AWS baseline was originally recorded as Experiment 006. It was moved to Experiment 007 so Experiment 006 could cover composed rc-demos → rc-pade interoperability. Historical evidence (commands, versions, validate/plan results) is preserved; only numbering and directory name changed.

## Boundary

- Generated `DevelopmentSession` remains an untrusted request.
- Unbound `aws.s3.bucket.write` in `pade plan` is success for **baseline preparation**, not fulfillment.
- Do not treat this document as proof of live S3 access.
