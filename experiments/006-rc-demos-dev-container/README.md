# Experiment 006 — composed rc-demos Profile → rc-pade

**Status: interoperability evidence captured through three semantic states — source-control projection redesign not completed.**

## Question

Can `rc-pade` consume the real composed dev-container `RuntimeConditionsProfile` produced by [runtimeconditions/rc-demos](https://github.com/runtimeconditions/rc-demos) (temporary pin: [ksteffe/rc-demos@13a85bd](https://github.com/ksteffe/rc-demos/commit/13a85bd4221797c94e209fad576a9d4ab89522f3) / upstream [PR #2](https://github.com/runtimeconditions/rc-demos/pull/2)) and generate appropriate PADE `DevelopmentSession` intent **without** copying, hand-normalizing, or inventing a simplified RC fixture?

## Sequence context

| Experiment | Proved |
|------------|--------|
| [001–004](../README.md) | RC → rc-pade → session for the S3 `PutObject` shape |
| [005C](../005c-deployed-pade/) | Deployed PADE identity/fulfillment substrate (GCE → broker → GitHub Material) |
| **006 (this)** | Real composed rc-demos Profile reaches `rc-pade`; explicit outside-PADE vs unmatched vs in-scope projection failure |
| [007](../007-s3-fulfillment/) | Deferred AWS S3 fulfillment baseline (formerly numbered 006) |

005C deliberately stopped before this RC → rc-pade integration seam. This experiment does **not** re-prove GCE identity, multi-issuer broker trust, Cloud Run, or GitHub Material.

## Architectural boundary

```text
ordinary application source
      ↓
Runtime Conditions profiler (go-rc-profiler)
      ↓
application.profiler.yaml
      ↓
RC profile composition (rc-demos)
      ↓
dev-container.profile.yaml   ← wire-format boundary
      ↓
rc-pade + ProjectionPolicy
      ↓
PADE DevelopmentSession (or explicit failure)
```

Neither project imports the other's implementation. The composed Profile is generated in a disposable sibling workspace and is not vendored into `rc-pade`.

## Reproduction / setup

```sh
bash experiments/006-rc-demos-dev-container/run.sh
```

Default policy is [`policy.yaml`](policy.yaml) (classification for this experiment). Overrideable environment:

| Variable | Default |
|----------|---------|
| `RC_DEMOS_REPO` | `https://github.com/ksteffe/rc-demos.git` |
| `RC_DEMOS_REF` | `13a85bd4221797c94e209fad576a9d4ab89522f3` (exact SHA, not a branch) |
| `EXTENSIONS_REPO` / `EXTENSIONS_REF` | `runtimeconditions/extensions` @ pinned tip |
| `PROFILER_REPO` / `PROFILER_REF` | `runtimeconditions/go-rc-profiler` @ pinned tip |
| `RC_PADE_POLICY` | `experiments/006-rc-demos-dev-container/policy.yaml` |
| `RC_PADE_EXPERIMENT_WORK` | `.work/experiment-006` |
| `RC_PADE_KEEP_WORK` | `0` |

To reproduce the original S3-only observation:

```sh
RC_PADE_POLICY=examples/s3-put-object/policy.yaml \
  bash experiments/006-rc-demos-dev-container/run.sh
```

**Temporary pin:** `RC_DEMOS_REF` points at the tested PR head on the fork. After [runtimeconditions/rc-demos#2](https://github.com/runtimeconditions/rc-demos/pull/2) merges, change the default to an upstream `runtimeconditions/rc-demos` commit.

## Observation sequence

### 1. Real composed Profile reached rc-pade

Compose succeeded. Generated Profile `web-demo-dev-container` contains three conditions (structural summary, not a hand-written fixture):

```text
content-api         kind=api              interface.type=http
site-analytics      kind=google.analytics interface.type=web   events=[page_view]
application-source  kind=source_control   interface.type=git   provider=github access=[fetch,pull,push]
```

### 2. Existing S3-only policy failed closed on `api/http`

With `examples/s3-put-object/policy.yaml`:

```text
rc-pade: no projection rule matches api/http
```

That proved the Profile was not hand-normalized away, and that unmatched conditions still fail closed.

### 3. Minimal policy/model extension: explicit `outsidePADE`

`ProjectionRule` gained an optional boolean `outsidePADE`:

- **unmatched** → error (`no projection rule matches …`)
- **`outsidePADE: true`** → accepted; **no** capability emitted
- **matched, not outside** → project via `operations` (existing path)

Conflicting `outsidePADE: true` plus `operations` is rejected. Unknown conditions are never treated as outside PADE merely by omission.

### 4. HTTP and Google Analytics classified outside PADE for this experiment

[`policy.yaml`](policy.yaml) matches by `kind` + `interfaceType` only:

| Match | Classification |
|-------|----------------|
| `api` / `http` | `outsidePADE: true` |
| `google.analytics` / `web` | `outsidePADE: true` |
| `source_control` / `git` | PADE-relevant (matched; intended for projection) |

### 5. Next failure: source-control projection

With the classification policy, generate again against the **same** composed Profile shape:

```text
rc-pade: condition source_control/git has no operations; the initial experiment only projects operation-backed conditions
```

The condition is matched and in scope, but the current projector only understands S3-style `interface.operations[].name`. The live Profile carries extension-defined structure:

```yaml
kind: source_control
interface:
  type: git
  provider: github
  access:
    - fetch
    - pull
    - push
```

(`provider` / `access` are present on the wire; today’s `RCInterface` model only unmarshals `type` and `operations`.)

### 6. What this teaches

Experiment 006 now isolates three distinct semantic states:

1. **Unknown / unclassified** → fail closed  
2. **Explicitly outside PADE** → accepted, no capability  
3. **PADE-relevant but not representable** by the current operations-based model → explicit projection failure  

No source-control matching abstraction, expression language, or name hardcoding was added. That redesign is deferred until a smallest general change is justified.

## Pins used

| Component | Ref |
|-----------|-----|
| rc-demos | `ksteffe/rc-demos` @ `13a85bd4221797c94e209fad576a9d4ab89522f3` |
| extensions | `7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7` |
| go-rc-profiler | `5d2e860e48842b89ec83414123a7e59228f61d36` |
| default policy | `experiments/006-rc-demos-dev-container/policy.yaml` |

Exact SHAs for each harness run are also written to gitignored `generated/environment.txt`.

## What 006 proves

- A real composed rc-demos Profile reaches `rc-pade` unchanged at the YAML boundary.
- Unmatched conditions still fail closed.
- Explicit `outsidePADE` classification is distinct from “ignored because unknown.”
- After classifying HTTP and Google Analytics outside PADE, the next executable blocker is projecting `source_control`/`git` without `operations[].name`.

## What 006 does not prove

- A correct DevelopmentSession for GitHub source-control authority
- How `access: [fetch, pull, push]` should map to PADE capabilities
- Whether `provider: github` belongs in Intent, policy, or elsewhere
- GCE identity / broker fulfillment / AWS (see [007](../007-s3-fulfillment/))
- Future single-install PADE packaging

## Result / current result

```text
Result: composed rc-demos Profile + classification policy establish
  unmatched → fail closed
  outsidePADE → accepted, no capability
  source_control/git → explicit "has no operations" failure

Next design work (not done here): smallest general way to project
extension-defined Condition structure beyond operations[].name.
```

## Next question

What is the smallest general projection change that can represent PADE-relevant conditions whose authority is expressed as extension fields (for example `access[]`) rather than `operations[].name`—without hardcoding rc-demos names or silently dropping unknowns?

## Future packaging observations

A longer-term developer experience might install one PADE-facing tool that discovers an RC Profile, projects relevant requirements, obtains Materials, and injects them into a Dev Container. Experiment 006 intentionally does **not** implement that packaging. The valuable boundary remains **RC wire format → projection → DevelopmentSession**, independent of whether `rc-pade` stays a separate binary.
