# Experiment 007 — S3 fulfillment (baseline preparation)

**Status: baseline preparation only — Experiment 007 is not complete.**

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

## Renumbering note

This AWS baseline was originally recorded as Experiment 006. It was moved to Experiment 007 so Experiment 006 could cover composed rc-demos → rc-pade interoperability. Historical evidence (commands, versions, validate/plan results) is preserved; only numbering and directory name changed.

## Boundary

- Generated `DevelopmentSession` remains an untrusted request.
- Unbound `aws.s3.bucket.write` in `pade plan` is success for **baseline preparation**, not fulfillment.
- Do not treat this document as proof of live S3 access.
