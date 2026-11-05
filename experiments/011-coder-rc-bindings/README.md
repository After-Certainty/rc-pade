# Experiment 011 — Coder ↔ RC bindings (validated projection → broker-only bindings)

**Status: adapter + unit coverage landed; live GCE-backed Coder → deployed broker fulfillment proven for `github.repo.read` and `aws.s3.bucket.write` through bindings produced by this adapter.**

## Question

Can a fail-closed adapter take:

1. a Runtime Conditions Profile,
2. trusted validation evidence for those exact Profile bytes,
3. an operator projection policy,
4. an operator capability allowlist, and
5. a broker-only binding template (pade-coder-shaped JSON),

and write a PADE Consumer bindings file that a GCE-backed Coder workspace can use with the deployed broker—without materializing any credential in the bindings file—and then fulfill real capabilities through `pade exec`?

## Adapter boundary

```text
validated RuntimeConditionsProfile
        + validation-report.yaml (SHA-256-bound)
        + operator ProjectionPolicy
        + operator capability allowlist
        + broker_binding.json (provider: broker only)
        ↓
experiments/011-coder-rc-bindings (this package)
        ↓
bindings.yaml  (broker coordinates per approved capability; no secrets)
        + optional DevelopmentSession
        ↓
pade exec --bindings <absolute path> --capability …
        ↓
deployed PADE broker → Material in child only
```

The adapter is **not** an RC validator and **not** a grant. It:

- requires absolute `--output` (Coder `module.pade.bindings_path` style);
- revokes prior local capabilities to empty `capabilities: {}` at the start of every run (fail closed);
- rejects mismatched, incomplete, rejected, or forged validation evidence;
- projects with unchanged `internal/projector` and fails closed on unsupported demand;
- refuses projected capabilities outside the operator allowlist;
- accepts only a complete broker-only JSON object (`provider: broker`, `https://` endpoint, non-empty audience, `identity` in `{gce,cursor}`);
- writes bindings and optional session at mode `0600` via temp-file rename.

Unit coverage is in `main_test.go` (trusted projection, thirteen fail-closed input cases, relative output rejection, no partial bindings on session write failure).

## Live environment

Manual validation from Coder workspace `pade-gcp` on GCE (same class as 005B/005C/007 Phase 3).

| Fact | Observation |
|------|-------------|
| Date (UTC) | 2026-11-05 |
| rc-pade branch | `experiment/011-coder-rc-bindings` @ `9d66ed8` (adapter + tests before this evidence commit) |
| PADE Consumer | release **v0.3.0** (`0467ed2`), installed via pade-coder module at `~/.local/bin/pade` |
| Broker | `https://pade-broker-754719312452.us-central1.run.app` |
| Identity | GCE metadata; `broker.identity: gce` |
| Attached service account | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` |
| Project / zone | `after-certainty` / `us-central1-a` |
| Durable AWS / GitHub credentials in workspace | **absent** |
| Module-managed `PADE_BINDINGS` | left untouched; live runs used absolute temp bindings under `/tmp/experiment-011-live*` |

## Live proof A — `github.repo.read`

Inputs:

| Input | Source |
|-------|--------|
| Profile | Experiment 009 Case A composed rc-demos Profile (1682 bytes, SHA-256 `53fe0bca5664c9b889304c881d6643cec163f449a9d02a91fd5a6d635ad62e19`) |
| Validation evidence | Same Case A acceptance, rewritten to this adapter’s KnownFields report shape (validator module/version, profile SHA-256/bytes, per-condition validity). **rcvalidate was not re-run in this session**; Profile bytes still matched the recorded hash. |
| Policy | [`experiments/008-rc-field-projection/policy.yaml`](../008-rc-field-projection/policy.yaml) |
| Allowlist | `github.repo.read,github.repo.write` |
| `broker_binding.json` | Live broker endpoint/audience, `identity: gce` |

Results:

```text
experiment-011: wrote 2 broker-only capability bindings
pade validate / plan / capabilities: OK (both capabilities broker-bound)
pade exec --capability github.repo.read → repo_full_name=After-Certainty/after-certainty
pade exec --capability github.repo.write → broker resolve denied (http 403)
incomplete adapter invocation → capabilities: {} (fail-closed revoke)
```

Least privilege held: this GCE subject remains authorized for read, not write, matching 005C.

## Live proof B — `aws.s3.bucket.write`

Inputs:

| Input | Source |
|-------|--------|
| Profile | [`examples/s3-put-object/runtime-conditions.yaml`](../../examples/s3-put-object/runtime-conditions.yaml) (282 bytes, SHA-256 `0f797117993eb198548046f7c3458ee43d7bcb6f827b0e2086a77a415fba4804`) |
| Validation evidence | Adapter-shaped report bound to those exact Profile bytes (same evidence shape the unit tests use). **Not a fresh rcvalidate of the S3 fixture** — this live cut proves the adapter→bindings→broker path for the S3 capability, not a new upstream validation gate run. |
| Policy | [`examples/s3-put-object/policy.yaml`](../../examples/s3-put-object/policy.yaml) |
| Allowlist | `aws.s3.bucket.write` |
| `broker_binding.json` | Same live broker / `gce` template |

Preflight: no ambient AWS credential env vars; `boto3.Session().get_credentials() is None`.

Child used unmodified [`experiments/003-source-to-session/app/storage.py`](../003-source-to-session/app/storage.py) `upload()` under boto3 `1.43.105`.

Results (safe observations only; PADE redacts Material values in captured output):

```text
experiment-011: wrote 1 broker-only capability bindings
broker resolve aws.s3.bucket.write: authorized
child Material present: AWS_ACCESS_KEY_ID / SECRET / SESSION_TOKEN / REGION / S3_BUCKET / S3_PREFIX
access key temporary ASIA prefix: true
PutObject experiment-007/experiment-011-broker-fulfillment-proof.txt: success (ETag present)
outside-prefix PutObject experiment-007-negative/…: AccessDenied
ListObjectsV2 on bucket: AccessDenied
```

Platform binding matched the Experiment 007 Phase 3 bucket/prefix/region (`after-certainty-rc-pade-007-1abcdf`, `experiment-007/`, `us-east-1`). No account ID, role ARN, raw tokens, or temporary credentials were recorded.

## What this proves

- The 011 adapter can produce Coder-usable broker-only bindings from validated-shaped RC input + operator policy/allowlist + pade-coder-shaped broker JSON.
- Those bindings are sufficient for live fulfillment on this GCE-backed Coder workspace against the deployed multi-issuer broker for both:
  - `github.repo.read` (GitHub Material → ordinary API read), and
  - `aws.s3.bucket.write` (broker-side STS Material → ordinary boto3 PutObject),
  with the same negative boundaries already established in 005C / 007 Phase 3.
- Fail-closed revoke works on incomplete invocation; module-managed bindings were not required for the proof and were not overwritten.

## What this does not prove

- A single automated harness that re-runs `rcvalidate` end-to-end before every live fulfillment (GitHub reused 009 Case A evidence; S3 used adapter-shaped evidence).
- That pade-coder itself emits `broker_binding.json` as a separate module artifact (the live JSON matched the shape the adapter requires; the installed module still writes YAML bindings directly).
- Authorization for subjects other than this allowlisted GCE service account.
- That Coder is an identity provider (it is not; GCE metadata is).

## Result

```text
Result: Experiment 011 adapter produced broker-only bindings that a GCE-backed
Coder workspace used with PADE v0.3.0 against the deployed broker to fulfill
github.repo.read and aws.s3.bucket.write. No durable provider credentials were
placed in the workspace or in the bindings file. JWT / GitHub / AWS secret
values were never printed.
```

Machine-readable pins: [`provenance.yaml`](provenance.yaml).

Module-managed handoff follow-up: [`pade-coder-handoff-followup.md`](pade-coder-handoff-followup.md) → [`checkpoint-a-provenance.yaml`](checkpoint-a-provenance.yaml), [`checkpoint-b-provenance.yaml`](checkpoint-b-provenance.yaml). Remaining findings (A7 fresh-home inputs, S3 `rcvalidate` reject, Case A carrying B) are listed in the runbook. The B1→B2 report shape bridge is [`project-validation-report.py`](project-validation-report.py) over [`checkpoint-b/`](checkpoint-b/).
