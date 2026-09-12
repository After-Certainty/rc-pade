# Experiment 004 — Coder workspace

## Question

Can the source → Runtime Conditions → rc-pade → PADE planning workflow operate normally inside an ordinary Coder development workspace, with Cursor as the developer interface, without requiring Coder, Cursor, Runtime Conditions, or PADE to contain special knowledge of one another?

## Architectural result

```text
Coder owns workspace lifecycle.
Cursor is the developer interface.
Runtime Conditions discovers workload demand.
rc-pade translates portable demand into portable session intent.
PADE validates/plans that intent.
```

None of those layers needs to absorb the vocabulary or implementation details of the others.

```text
Coder workspace
      ↓
Cursor
      ↓
ordinary application source
      ↓
Runtime Conditions profiler
      ↓
RuntimeConditionsProfile
      ↓
rc-pade
      ↓
PADE DevelopmentSession
      ↓
PADE validate / plan
```

## What Coder contributed

Coder provided a real disposable remote development environment and nothing more. Environment facts for the manual proof are recorded externally in `generated/environment.txt`. No Coder fields are written into Runtime Conditions profiles, rc-pade projection policy, or PADE portable intent.

## Boundary

This experiment stops before capability fulfillment. It does **not**:

- provision an S3 bucket
- create AWS credentials or IAM policy
- modify PADE broker behavior
- modify Runtime Conditions semantics
- add Coder- or Cursor-specific concepts to RC or PADE
- treat the generated `DevelopmentSession` as authorization
- attempt cloud-resource fulfillment

The next experiment will likely be:

```text
Coder workspace identity
        ↓
PADE broker
        ↓
bounded AWS material / derived authority
        ↓
ordinary boto3 application
```

Experiment 004 does not solve that.

## Reuse

The ordinary boto3 direct-client source and the Runtime Conditions generation path are reused from Experiment 003 (`experiments/003-source-to-session/`). This experiment does not maintain a second semantically different application fixture.

Projection continues to use `examples/s3-put-object/policy.yaml`. The expected session remains Experiment 002's golden `DevelopmentSession` (`aws.s3.bucket.write`).

## PADE CLI

Against the generated session, this experiment invokes the real PADE reference Consumer (pinned in `provenance.yaml`):

```bash
go run ./cmd/pade validate -f generated/development-session.yaml
go run ./cmd/pade plan -f generated/development-session.yaml
```

`pade plan` is side-effect-free and does not require a broker or bindings. An unbound `aws.s3.bucket.write` capability in the plan is expected success for this experiment: intent is validated and planned, not fulfilled.

## Run (manual Coder / Cursor proof)

From a Cursor-connected Coder workspace:

```sh
bash experiments/004-coder-workspace/run.sh
```

Set `RC_PADE_EXPERIMENT_WORK` to override the heavy work directory. By default the script uses `.work/experiment-004`.

Generated artifacts (gitignored) under `experiments/004-coder-workspace/generated/`:

- `runtime-conditions.yaml`
- `development-session.yaml`
- `pade-plan.txt`
- `environment.txt`

If Go is missing, the script bootstraps mise and the Go version from this repository's `mise.toml` into the user-local path. That is ordinary developer toolchain setup, not a Coder integration. The script invokes a concrete Go binary (not mise shims) when running PADE so a nested PADE checkout's untrusted `mise.toml` cannot intercept `go`.

## Deterministic CI vs manual proof

| Check | Where |
|-------|--------|
| Project pinned Experiment 002 RC profile → `pade validate` / `pade plan` | `.github/workflows/experiment-004.yml` |
| Full source → RC profiler → rc-pade → PADE inside Coder | Manual: `run.sh` in a Cursor-connected Coder workspace |

CI does not assert `CODER=true`. The Coder-workspace execution remains a documented manual integration experiment.

## Observed GitHub authority boundary

The successful manual run also exposed a separate development-session boundary: the Coder workspace had enough GitHub access to clone and read the repository, but it did not have authority to push the resulting branch back to GitHub.

This was not treated as a failure of the source → RC → rc-pade → PADE experiment, and the workspace was not granted broader GitHub credentials merely to publish the result. Instead, the completed Git history was exported from the Coder workspace with `git bundle`, copied across the workspace boundary to the developer's local machine, and pushed from there using the local machine's existing GitHub write authority.

That distinction is useful evidence for the broader model:

```text
application-derived demand
  → e.g. aws.s3.bucket.write

development-workflow authority
  → e.g. permission to push to the source repository
```

The latter is not application runtime demand and therefore should not be inferred by Runtime Conditions from application source. It may eventually be relevant to PADE or adjacent developer-session policy, but Experiment 004 intentionally does not solve it. The bundle transfer preserves the experiment's trust boundary rather than hiding it by introducing unrelated credentials.

## Acceptance criteria

1. Cursor is connected to a real Coder workspace.
2. The experiment is run from that workspace.
3. Ordinary boto3 source is the starting application input.
4. The real Runtime Conditions profiling path produces the expected S3 `PutObject` condition.
5. `rc-pade` projects that condition through the existing policy.
6. The resulting PADE `DevelopmentSession` contains `aws.s3.bucket.write`.
7. PADE can validate and plan that generated session intent.
8. No Coder-specific vocabulary is added to RC, rc-pade policy semantics, or PADE portable intent.
9. No AWS account, region, bucket identity, credentials, IAM permissions, environment variables, or provider binding are inferred without evidence.
10. The experiment documents that Coder contributed only a real disposable remote development environment.
