# Experiment 008 — RC field projection (`source_control` / `git`)

**Status: hypothesis supported for the live rc-demos git condition — not final architecture.**

## Hypothesis

Can `rc-pade` project the real composed rc-demos `source_control`/`git` condition into PADE GitHub capability intent using:

1. **opaque preservation** of extension-defined `interface` fields, and
2. a **bounded declarative matcher** (`equals`, `contains`, and AND only),

without making the projector extension-specific, without a general query language, and without weakening Experiment 006 invariants (unknown fail-closed, `outsidePADE`, exactly one top-level classifying rule)?

This is the A/C family from [`docs/rc-projection-policy-design.md`](../../docs/rc-projection-policy-design.md). A successful result here means A/C **survived contact with this real extension shape**. It does **not** establish A/C as permanent projection architecture.

## Mechanism tested

| Layer | Mechanism |
|-------|-----------|
| Classification | Exactly one top-level rule matched by `kind` + `interfaceType` |
| Hard requirements | Rule-level `require` predicates (`equals` / `contains`, AND) |
| Capability emissions | Intra-rule `project` clauses; each clause fires when its `when` AND holds |
| Exhaustiveness | Tiny `cover` list: every observed value on a covered path must be accounted for by a **firing** clause with a direct `contains` on that path |
| Legacy S3 | Unchanged `operations` map path (kept alongside; not migrated) |

**Important evidence about the matcher:** simple `equals`/`contains`/`when` alone was not enough for fail-closed authority handling. Explicit exhaustiveness via `cover` was required so unrecognized `access[]` values cannot be silently omitted. That is mild pressure on A/C, not a full falsification for this experiment.

Provisional PADE policy (Reading 1 — independent access translations):

| access | capability | access field |
|--------|------------|--------------|
| fetch | `github.repo.read` | read |
| pull | `github.repo.read` | read |
| push | `github.repo.write` | write |
| clone | `github.repo.read` | read |

Write does not imply read. Provider `github` is enforced by `require`, not by top-level classification.

## Primary input

The **real composed** rc-demos dev-container Profile (same pins as Experiment 006), not a handwritten source_control fixture.

```sh
bash experiments/008-rc-field-projection/run.sh
```

The harness deletes `generated/` and the disposable work tree, recomposes from pinned siblings, then runs `rc-pade generate`.

## Provenance (inherited from Experiment 006)

| Component | Pin |
|-----------|-----|
| rc-demos | `ksteffe/rc-demos` @ `13a85bd4221797c94e209fad576a9d4ab89522f3` |
| extensions | `7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7` |
| go-rc-profiler | `5d2e860e48842b89ec83414123a7e59228f61d36` |
| source-control URI on Profile | `…/source-control/0.1.0/…` |

Exact SHAs for each harness run are written to gitignored `generated/environment.txt`. Pins are not tip-of-tree.

## Observed successful DevelopmentSession

```yaml
apiVersion: pade.local/v1alpha1
kind: DevelopmentSession
metadata:
  name: web-demo-dev-container
  annotations:
    rc-pade.local/source-profile: web-demo-dev-container
    rc-pade.local/source-workload-uri: https://github.com/runtimeconditions/rc-demos/tree/main/dev-container-profile#dev-container
    rc-pade.local/source-workload-version: demo
spec:
  capabilities:
    github.repo.read:
      access: read
      required: true
    github.repo.write:
      access: write
      required: true
```

HTTP (`api`/`http`) and Google Analytics (`google.analytics`/`web`) were explicitly `outsidePADE` under **this experiment’s operator policy** and emitted no capabilities. No unexpected capabilities appeared.

## Result summary

```text
Result: SUCCESS for the live git case
  - opaque Fields preserved provider/access through unmarshal
  - real composed Profile → github.repo.read + github.repo.write
  - fetch+pull coalesce to one read capability
  - HTTP and Analytics accepted as outsidePADE
  - legacy S3 operations path still passes unit tests
  - unknown access / provider mismatch / missing fields fail closed
  - project-mode zero emission fails explicitly
  - A/C survived this experiment; not declared final architecture
```

## Falsification conditions

Stop and report the boundary (do not grow architecture) if:

- the matcher needs OR / regex / JSONPath / scripting for the basic git case
- preserving opaque fields breaks S3 validation or causes unacceptable ambiguity
- exhaustiveness requires large generic machinery beyond tiny `cover`
- dual `operations` + `project` paths become so awkward the mechanism is not actually generic
- source_control needs procedural interpretation declarative predicates cannot express
- multi-capability emission requires weakening single top-level classification
- safe projection is impossible without resolving extension identity first

**None of these were hit in Experiment 008.**

## Unresolved pressures (not solved here)

- Extension identity/version is **not** part of projection matching (pinned only by provenance / Profile `extensions[]`)
- Top-level classification remains **kind + interfaceType only**
- **Provider-aware classification** remains unresolved (`provider: github` is rule-level `require`, not a classification discriminator; independent github/gitlab policies may challenge this later)
- S3 still uses the **legacy `operations` path** (not migrated onto the field matcher)
- HTTP / Kubernetes / NATS have **not** validated generality of the matcher
- `cover` may **not** generalize beyond this access-array case
- No broker fulfillment, repository identity, credentials, or GitHub API behavior was tested

## Safety invariants preserved

| Case | Behavior |
|------|----------|
| Unknown / unmatched | Fail closed |
| `outsidePADE` | Accept; emit no capability |
| Exactly one top-level rule | Ambiguous multi-match still errors |
| Optional RC condition | `required: !optional` on project emissions |
| Cover | Observed access values accounted for only by **firing** clauses |
| Project-mode zero emission | Explicit error (not silent accept) |

## Sequence context

| Experiment | Role |
|------------|------|
| [006](../006-rc-demos-dev-container/) | Real composed Profile reaches rc-pade; git fails on operations-only model |
| **008 (this)** | Opaque fields + bounded matcher project git → GitHub capability intent |
| [005C](../005c-deployed-pade/) | Fulfillment substrate for `github.repo.read` (not re-run here) |
| [007](../007-s3-fulfillment/) | S3 fulfillment baseline (separate track) |

## Policy used

See [`policy.yaml`](policy.yaml).
