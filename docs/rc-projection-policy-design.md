# RC → PADE projection policy design

**Branch:** `design/rc-projection-policy`  
**Status:** design and planning only — no projector behavior change on this branch  
**Date of investigation:** 2026-09-16

This document answers: what projection model should `rc-pade` test next, given Experiment 006 evidence and representative Runtime Conditions extension shapes.

It does **not** implement a new projection abstraction. The recommendation is the smallest useful **hypothesis to test next**, not a permanent architecture.

---

## Revisions inspected

These commits were inspected for this design investigation. They are **not** asserted to form a synchronized multi-repo release.

| Component | Repository | Commit SHA | Role |
|-----------|------------|------------|------|
| rc-pade | `After-Certainty/rc-pade` | `468838d0a25f3ab14b6da6b8e02189f03d554d1d` | Design branch base (`main` including merged Experiment 006) |
| extensions | `runtimeconditions/extensions` | `7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7` | Experiment 006 pin; catalog shapes inspected |
| spec | `runtimeconditions/spec` | `f84bf612feb77c87a21c6639e8c7fdec67833d1e` | Spec tip inspected for bridges, Profile/extension rules — **independent** of the extensions pin |
| rc-demos | `ksteffe/rc-demos` (temporary fork) | `13a85bd4221797c94e209fad576a9d4ab89522f3` | Experiment 006 composed Profile source |
| go-rc-profiler | `runtimeconditions/go-rc-profiler` | `5d2e860e48842b89ec83414123a7e59228f61d36` | Experiment 006 pin (compose chain) |

Runtime Conditions repositories were not modified. Disposable clones lived under gitignored `.work/design-rc-projection/`.

---

## 1. Problem statement

`rc-pade` must map selected Runtime Conditions Profile semantics into PADE `DevelopmentSession` capability intent under this boundary:

```text
Runtime Conditions Profile
        ↓
rc-pade projection policy
        ↓
PADE DevelopmentSession
```

Runtime Conditions owns workload requirement vocabulary.  
`rc-pade` owns translation from selected RC semantics into PADE capability intent.  
PADE owns authorization and Material fulfillment.

Experiment 006 proved that a real composed Profile reaches `rc-pade`, but the current projector only understands S3-style `interface.operations[].name`. Extension-defined authority often uses other shapes (`access[]`, `method`/`path`, multi-field K8s ops, `events`, engine-only datastore, and so on).

The design question is how to project **arbitrary extension-defined** Condition semantics **without**:

- teaching `rc-pade` core about every extension;
- hardcoding condition instance names;
- silently ignoring unknown fields;
- assuming every extension uses `operations[].name`;
- introducing an excessively powerful query/expression language without evidence;
- coupling `rc-pade` to Runtime Conditions implementation code;
- requiring Runtime Conditions itself to know about PADE.

---

## 2. Evidence from Experiment 006

Location: [`experiments/006-rc-demos-dev-container/`](../experiments/006-rc-demos-dev-container/).

Executable evidence established:

1. A real composed Runtime Conditions dev-container Profile from rc-demos reaches `rc-pade` unchanged at the wire-format boundary.
2. Unknown / unclassified conditions fail closed (`no projection rule matches api/http` under an S3-only policy).
3. Projection policy can explicitly classify a condition as `outsidePADE`, which accepts the condition without emitting a PADE capability.
4. A condition can be recognized as PADE-relevant but still fail because the current projector only understands `interface.operations[].name`.
5. The real `source_control` / `git` condition expresses authority through `provider: github` and `access: [fetch, pull, push]`, not `operations[].name`.

Composed Profile conditions (structural summary from `generated/dev-container.profile.yaml`):

| name | kind | interface.type | authority-shaped fields |
|------|------|----------------|-------------------------|
| content-api | `api` | `http` | `spec` + `operations[].method/path` |
| site-analytics | `google.analytics` | `web` | `events[]` + `configuration.env` |
| application-source | `source_control` | `git` | `provider`, `access[]` |

Experiment 006 classification policy matched by `kind` + `interfaceType` only: HTTP and Analytics → `outsidePADE`; `source_control`/`git` → in-scope, then failed with “has no operations”.

Root cause in current code:

- [`internal/model/rc.go`](../internal/model/rc.go) unmarshals only `interface.type` and `operations[].name`; other wire fields are dropped.
- [`internal/projector/projector.go`](../internal/projector/projector.go) requires non-empty `operations` for non-`outsidePADE` rules and maps by operation name.

006 deliberately did **not** design source-control projection semantics.

---

## 3. Evidence from representative RC extensions

Inspected under extensions `@7a08c8b9…`. Patterns below are from published extension definitions and examples—not from PADE assumptions.

### AWS S3 (`aws.s3` / `bucket`)

Authority via named operations:

```yaml
kind: aws.s3
interface:
  type: bucket
  operations:
    - name: PutObject
```

Optional `interface.operations[].role` ∈ `{destination, source}`. This is the shape `rc-pade` originally modeled.

### Source control (`source_control` / `git`)

```yaml
kind: source_control
interface:
  type: git
  provider: github
  access:
    - clone
    - fetch
    - pull
    - push
```

No `operations` array. Extension `fieldValues` enumerate `interface.access[]` ∈ `{clone, fetch, pull, push}` and require `provider`.

**RC wording about access values:** the extension describes “Git repository access” required by a workload; credentials and concrete repository locations remain target-environment configuration. The definition enumerates allowed strings. It does **not** define what each value means for PADE, whether values are independent authorities, or whether workflows imply combined authority (for example whether `pull` implies `fetch`, or whether `push` should emit write alone or read+write). Those are **PADE projection-policy questions**, not RC semantic facts. See §8 and §15.

### Common HTTP API (`api` / `http`)

Authority may be expressed as:

- `interface.operations[].method` + `interface.operations[].path` (not `{name: …}`), and/or
- `interface.spec` (`format`/`uri`/`version`, e.g. OpenAPI) instead of or in addition to enumerated operations.

Experiment 006’s `content-api` condition uses both `spec` and a `GET /message` operation.

### Google Analytics (`google.analytics` / `web`)

```yaml
kind: google.analytics
interface:
  type: web
  events:
    - page_view
configuration:
  env:
    - property: measurementId
      name: GA_MEASUREMENT_ID
```

No generic operation concept. Demand is event-shaped plus configuration binding.

### Kubernetes (`kubernetes` / `api`)

Operations encode multi-field semantic authority, for example:

- resource form: `verb`, `apiGroup`, `apiVersion`, `resource`, `scope` (+ optional `subresource`)
- connect form: `verb: connect` + `method` + resource fields
- non-resource form: `path` + `method`

### NATS (`nats` / `service`)

Operations use `resource` + `action`, plus branch-specific fields such as `subject`, `stream`, `bucket`, `name`, `subjects`. Authoring docs stress a fixed Condition operation form, not a free-form runtime query language.

### Datastore / cache (common-integrations)

Examples may describe integration type/engine only (`interface.type`, optional `interface.engine`) **without** enumerating an authority operation. Projection may often be `outsidePADE` or environment-config classification rather than capability emission—but the wire shape still must not be silently dropped if a rule claims the condition is in scope.

### Cross-extension pattern summary

| Pattern | Examples |
|---------|----------|
| Named ops (`operations[].name`) | S3 |
| Multi-field ops (not name-keyed) | HTTP method/path, K8s, NATS |
| Non-operation authority enums | source_control `access[]` |
| Event / config demand | Google Analytics |
| Type/engine only | datastore, cache |
| Spec reference instead of enum ops | HTTP `interface.spec` |

There is **no** single shared authority IR across these extensions.

---

## 4. RC architectural constraints

### Profiles declare exact extension identifiers

Profiles include an `extensions:` array of immutable absolute URIs. Semantic changes require a new exact extension identifier. Resolved `metadata.id` must equal the declared URI. Condition `kind` / `interface.type` are interpreted in the context of the declared extension set—not as globally stable identities by themselves.

### Semantic bridges are authoring artifacts

Inspected:

- extensions `SERVICE_OPERATIONS_SEMANTIC_BRIDGES.md` `@7a08c8b9…`
- spec `docs/guides/service-operation-authoring.md` and `docs/sixth-draft.md` `@f84bf612…`

**Interpretation confirmed:**

- Semantic bridges are extension-authoring artifacts.
- They translate authoritative provider/service operations into RC Condition semantics.
- They are **not** intended as runtime input to platform adapters.
- The published extension definition (and Profile that uses its vocabulary) stands alone for consumers.

Therefore this design does **not** propose that `rc-pade` consume semantic-bridge YAML at projection time.

### Adapters consume Profile + extension vocabulary

RC docs state that platform adapters consume generated profiles and extension definitions (vocabulary + validation). Bridges/inventories/service mappings may remain useful at **build time** for authors or compilers; they are not the runtime contract.

### Machine-readable extension vocabulary

Extension definitions expose `kinds`, `interfaceTypes`, `conditionFields`, `interfaceFields`, `fieldValues`, and JSON Schemas. That metadata can tell a consumer that `interface.access[]` is a valid field with enumerated values. It does **not** say that `push` should become `github.repo.write`. The latter remains an `rc-pade` / operator policy decision.

---

## 5. PADE / rc-pade constraints

From the root README and current code:

- RC conditions are demand, not grants.
- Projection policy owns opinionated translation to opaque PADE capability names.
- A generated `DevelopmentSession` remains an untrusted request; PADE still authorizes fulfillment.
- Neither side imports the other’s implementation—wire formats only.
- The adapter must not infer credentials, account/region/bucket identity, IAM actions, env injection, or provider binding.
- Policy format `rc-pade.local/v1alpha1` is deliberately provisional.

Current matching is exact `kind` + `interfaceType`. Current projection path is `operations[name] → {capability, access}`.

---

## 6. Required safety properties

Any proposed design **must** preserve:

| Classification | Behavior |
|----------------|----------|
| Unknown / unclassified | Fail closed |
| Explicitly `outsidePADE` | Accept; emit **no** PADE capability |
| Explicitly projected | Emit PADE capability intent |

Do not treat a missing rule as outside PADE. Do not silently drop unmatched operations or authority-bearing fields on an in-scope rule. Conflicting `outsidePADE` plus projection mappings must remain an error.

### Projection cardinality

Today’s projector requires **exactly one** top-level `ProjectionRule` to match each RC condition. Duplicate top-level matches fail with “multiple projection rules match …”. That failure protects against **ambiguous classification** (for example two rules both claiming `source_control`/`git`, one `outsidePADE` and one projecting).

Experiment 008’s `source_control` condition may still legitimately imply **multiple** PADE capabilities from **one** condition—for example `access: [fetch, pull, push]` independently implying both read and write capability intent.

These must stay distinct:

| Layer | Cardinality | Role |
|-------|-------------|------|
| Classification | Exactly one unambiguous top-level rule per condition | Decide unknown vs `outsidePADE` vs in-scope projection |
| Capability projection | Zero or more explicit projection clauses **within** that rule | Emit PADE capability intent |

**Do not** solve multi-capability demand by allowing arbitrary multiple top-level rules to match one condition. That would weaken the ambiguous-classification guard.

For A/C, the bounded mechanism to evaluate is: **one classifying rule** containing **multiple conditional projection clauses** (or an equivalent intra-rule list), each of which may emit a capability when its predicates match. Permanent YAML syntax is not settled here; Experiment 008 must make this cardinality requirement explicit and testable.

---

## 7. Candidate designs

### Option A — Declarative field/value matching in ProjectionPolicy

Policy rules continue to classify by `kind` + `interfaceType` (and possibly more). A single matched rule may then evaluate selected fields with a **small** predicate vocabulary (scalar equality, array membership, conjunction of required predicates) and emit **zero or more** capabilities via explicit intra-rule projection clauses.

### Option B — Extension-specific projection adapters

Per-extension code (or plugins) understands that extension’s vocabulary and emits capabilities / abstract facts. Core stays thin; knowledge moves into adapters.

### Option C — Declarative policy over preserved arbitrary Condition data

Stop modeling every extension field in Go structs. Preserve extension-defined `interface` (and relevant condition) data as generic structured data; policy identifies which fields matter.

### Option D — PADE projection metadata associated with extensions

Ship PADE-specific mapping artifacts beside an RC extension release or in a separate registry—owned outside the RC extension itself unless RC explicitly adopts PADE coupling (which it should not by default).

### Option E — Semantic normalization layer

Normalize diverse RC shapes into a small intermediate representation (e.g. resource / action / provider / target) before mapping to PADE capabilities.

### A and C are one design family

Option A without Option C cannot work against live Profiles: today’s typed `RCInterface` drops `provider`/`access` before any matcher runs. Option C without some form of A leaves opaque data with no projection rule language. **A+C is the coherent declarative family:** preserve wire-shaped extension data, then match with a bounded declarative vocabulary.

---

## 8. Concrete YAML examples for viable candidates

Illustrative provisional syntax only. Not implemented on this branch.

### A/C — S3 (retain today’s meaning)

```yaml
apiVersion: rc-pade.local/v1alpha1
kind: ProjectionPolicy
rules:
  - match:
      kind: aws.s3
      interfaceType: bucket
    project:
      - when:
          fields:
            - path: interface.operations[].name
              equals: PutObject
        capability: aws.s3.bucket.write
        access: write
```

### A/C — source_control/git (Experiment 006 shape)

RC enumerates `access` values; **PADE policy chooses** capability mapping. Two readings must be considered:

**Reading 1 — independent translations** (each matching access value may contribute a capability; duplicates coalesce):

```yaml
  - match:
      kind: source_control
      interfaceType: git
    project:
      - when:
          fields:
            - path: interface.provider
              equals: github
            - path: interface.access[]
              contains: fetch
        capability: github.repo.read
        access: read
      - when:
          fields:
            - path: interface.provider
              equals: github
            - path: interface.access[]
              contains: pull
        capability: github.repo.read
        access: read
      - when:
          fields:
            - path: interface.provider
              equals: github
            - path: interface.access[]
              contains: push
        capability: github.repo.write
        access: write
```

Under Reading 1, Experiment 006’s `[fetch, pull, push]` would emit both read and write capability intent from **one** classifying rule with **multiple** `project` clauses (write does not automatically replace read unless policy says so). This is the cardinality pattern Experiment 008 should exercise.

**Reading 2 — combined / workflow authority** (policy treats a set of access values as one workflow grant). Expressible with AND of membership predicates—no separate `containsAll` primitive required:

```yaml
  - match:
      kind: source_control
      interfaceType: git
    project:
      - when:
          fields:
            - path: interface.provider
              equals: github
            - path: interface.access[]
              contains: fetch
            - path: interface.access[]
              contains: pull
            - path: interface.access[]
              contains: push
        # Provisional: one combined intent chosen by the operator policy.
        capability: github.repo.write
        access: write
```

Reading 2 is also a **policy** choice. RC does not state that `[fetch, pull, push]` means “write subsumes read” or “single Material.” Experiment 008 should pick one reading explicitly and document it as provisional PADE policy, not as RC truth. Prefer Reading 1 for the first executable test so multi-capability emission within one rule is observed.

### A/C — HTTP outside PADE (006 classification)

```yaml
  - match:
      kind: api
      interfaceType: http
    outsidePADE: true
```

### A/C — HTTP projected by method/path (comparative sketch)

```yaml
  - match:
      kind: api
      interfaceType: http
    project:
      - when:
          fields:
            - path: interface.operations[].method
              equals: GET
            - path: interface.operations[].path
              equals: /message
        capability: demo.content-api.read
        access: read
```

Note: HTTP may also use `interface.spec` without enumerated operations. A matcher that only understands operation elements would still need an explicit `outsidePADE` or a separate `spec`-based rule—fail closed if in-scope but unmatched.

### A/C — Kubernetes comparative sketch

```yaml
  - match:
      kind: kubernetes
      interfaceType: api
    project:
      - when:
          fields:
            - path: interface.operations[].verb
              equals: get
            - path: interface.operations[].resource
              equals: configmaps
            - path: interface.operations[].scope
              equals: namespaced
        capability: k8s.configmaps.read
        access: read
```

### A/C — NATS comparative sketch

```yaml
  - match:
      kind: nats
      interfaceType: service
    project:
      - when:
          fields:
            - path: interface.operations[].resource
              equals: subject
            - path: interface.operations[].action
              equals: publish
        capability: nats.subject.publish
        access: write
```

### Bounded matcher vocabulary (initial Experiment 008)

Justified by inspected extensions and Experiment 008 needs:

| Construct | Meaning |
|-----------|---------|
| `path` | Dot path from condition root; `[]` means “any array element / membership target” |
| `equals` | Scalar equality |
| `contains` | Array membership (one value) |
| Clause `when.fields` | Conjunction (AND) of predicates |
| Multiple `project` clauses **within one classifying rule** | Zero or more explicit capability emissions; capability name collisions must not silently weaken access |

No inspected extension or Experiment 008 requirement needs a dedicated `containsAll` operator. Multi-value array requirements, if any, can be expressed as AND of several `contains` predicates. List `containsAll` as a possible **future sugar** only if evidence shows the expanded form is too noisy.

**Not in scope for next experiment:** `containsAll`, JSONPath/JMESPath, regex, OR trees, functions, joins across conditions, arbitrary scripting, or allowing multiple top-level rules to match one condition.

### Option B sketch

```text
plugins/
  source_control_git.so   # or Go plugin / separate module
  aws_s3_bucket.so
```

Core: classify match → dispatch adapter → merge capabilities. Policy might only select which adapters are enabled and map adapter facts → capability names—or adapters emit capabilities directly (stronger coupling).

### Option D sketch (external catalog, not inside RC extension)

```yaml
# pade-projection-catalog.yaml (owned by PADE / operator, not RC)
apiVersion: pade.projection.example/v1alpha1
kind: ExtensionProjection
extensionId: https://runtimeconditions.io/extensions/source-control/0.1.0/runtimeconditions.extension.yaml
rules:
  - ...
```

### Option E sketch

```yaml
# Intermediate fact (hypothetical)
resource: repo
provider: github
actions: [read, write]
target: unresolved  # still not in Profile
```

Then map facts → PADE capabilities. Requires a normalization function per extension shape—functionally overlapping B, with a shared IR that current extensions do not obviously share.

---

## 9. Advantages / disadvantages

### Comparison table

| Concern | A/C declarative field match + opaque preserve | B per-extension adapters | D external PADE catalog | E normalization IR |
|---------|-----------------------------------------------|--------------------------|-------------------------|--------------------|
| Avoid teaching core every extension | Yes (policy carries field knowledge) | Yes (plugins carry it) | Yes (catalog carries it) | Partial (normalizers still extension-specific) |
| Avoid condition-name hardcoding | Yes | Yes | Yes | Yes |
| Avoid assuming `operations[].name` | Yes | Yes | Yes | Yes |
| Preserve fail-closed / outsidePADE | Natural fit | Natural fit | Natural fit | Natural fit if IR stage is fail-closed |
| Expression-language risk | Real if vocabulary grows | Lower in core; logic in code | Same as A if catalog uses rich matchers | Lower if IR is tiny; high if IR is forced |
| Couples to RC implementation code | No | Risk if adapters import RC pkgs | No | No |
| Requires RC to know PADE | No | No | Only if catalog is forced into RC releases | No |
| Fits heterogeneous shapes (git/HTTP/K8s/GA/datastore) | Strong for field-shaped demand; weak if logic needs procedures | Strong | Strong if catalogs exist | Weak: shapes do not share one IR |
| Versioning / extension-id awareness | Can add match on extension URI later | Adapters version with code | Catalog keyed by extension URI naturally | Normalizers version with code |
| Third-party extensibility | Policy files | Plugin packaging | Catalog distribution | Normalizer packaging |
| Smallest next executable experiment | Strong candidate | Heavier packaging/plugin surface | Premature supply-chain/registry | Needs justified shared IR first |
| Future single-tool packaging | Policy remains data | Plugins complicate one-tool DX | Extra artifact to ship/trust | Extra stage inside tool |

### Option E evaluation (not pre-rejected)

Current evidence makes E **appear unlikely** to be the smallest next step:

- Google Analytics uses events, not resource/action.
- Source control uses provider + access enums.
- Datastore/cache may have no action at all.
- Kubernetes authority is a multi-field tuple, not a single action string.
- NATS looks closest to resource/action, but even there fields are branch-specific.

A forced IR would either erase distinctions or become a union type that reintroduces extension-specific structure under new names—i.e. adapters in disguise.

**However**, the design branch must allow E to falsify the A/C recommendation. E would become preferable if investigation (or Experiment 008 fallout) showed that a small shared IR covers S3, git, HTTP, K8s, and NATS with **less** policy surface and **clearer** safety than field predicates—without silent loss. That bar is not met by current evidence, but it is not ruled out a priori.

---

## 10. Versioning implications

- Profiles already pin immutable extension URIs.
- Today’s `rc-pade` matches only `kind` + `interfaceType`.
- Two extension releases can reuse the same `kind` / `interface.type` strings while changing allowed values or meaning of fields such as `access`.
- Therefore projection correctness is **at risk** if policy assumes kind/type identity is enough across years of extension evolution.

**Documented stance for next experiment:** continue matching primarily on `kind` + `interfaceType` for the smallest test, but record that **extension identifier (and thus semantic version embedded in the URI) should participate in projection matching before production reliance**. Implementation of extension resolution is explicitly out of scope for the next experiment.

Optional future match field (not implemented now):

```yaml
match:
  kind: source_control
  interfaceType: git
  extensionId: https://runtimeconditions.io/extensions/source-control/0.1.0/runtimeconditions.extension.yaml
```

---

## 11. Extension-resolution implications

Full resolution (fetching definitions, verifying `metadata.id`, validating Conditions against schemas) would enable:

- confirming that matched field paths exist in the extension vocabulary;
- rejecting profiles that declare vocabulary they do not include;
- pinning policy to extension identity.

It is **not** required to answer whether a small field matcher can project Experiment 006’s git condition. Next experiment should consume the already-composed Profile wire document and operator policy only—same as 006—while the design doc keeps resolution as a follow-on hardening step.

Using extension definitions for **validation of field path existence** is compatible with keeping **capability naming** in `rc-pade` policy. Knowing `interface.access[]` is valid ≠ knowing `push` → `github.repo.write`.

---

## 12. Trust / supply-chain implications

| Approach | Trust notes |
|----------|-------------|
| A/C policy in-repo / operator-controlled | Operator trusts their own policy; Profile still untrusted demand |
| B plugins | Code execution surface; signing/versioning of plugins |
| D external catalog | Separate artifact trust; risk of catalog/extension skew; tempting to co-publish with RC (couples ecosystems) |
| E normalizers | Same as B if code-shaped; same as A if declarative mapping tables |

Do not place PADE mapping inside Runtime Conditions extension releases by default: that would couple RC authors to PADE and invert ownership. An external catalog (D) can work later if versioned against extension URIs and distributed under PADE/operator trust—not as an RC runtime dependency.

Semantic bridges must not become a second trust path for adapters.

---

## 13. Impact on future single-tool packaging

Longer-term DX may install one PADE-facing tool that discovers RC demand, projects, obtains Materials, and injects into a Dev Container. Internally the seam remains:

```text
RC → projection boundary → PADE
```

`rc-pade` may remain an architectural/testable boundary without forever remaining a separately installed executable.

Packaging must not force the projection design:

- A/C keeps projection as data (policy YAML) easy to embed.
- B/D add distribution complexity.
- E adds an internal stage regardless of packaging.

Semantic contract first; packaging later.

---

## 14. What NOT to solve yet

- Implementing opaque interface preservation or field matchers
- Extension resolution / schema validation against extension definitions
- Plugin systems or external projection catalogs
- Normalization IR implementation
- Live GitHub Material fulfillment (see Experiment 005C substrate; not this seam)
- AWS S3 fulfillment (Experiment 007)
- Dev Container installation / single-tool packaging
- Consuming semantic-bridge authoring artifacts at runtime
- Declaring a permanent projection architecture

---

## 15. Recommended smallest next experiment

### Working recommendation (falsifiable)

**Test next:** Option **A/C** — preserve extension-defined Condition interface data as opaque structured data, and project with a **bounded** declarative field/value matcher in `ProjectionPolicy`, while preserving fail-closed and `outsidePADE`.

**Why this appears smallest given current evidence:**

- Experiment 006’s blocker is specifically “fields exist on the wire but are dropped / not matchable,” not “we lack a git plugin.”
- Representative extensions are heterogeneous; a shared IR (E) is not evidenced.
- Capability naming must remain operator/PADE policy (not RC, not bridges).
- A tiny predicate set (equals / contains / AND) is enough to express S3 name ops, git access membership, and comparative HTTP/K8s/NATS sketches without JSONPath.
- One classifying rule with multiple intra-rule projection clauses covers multi-capability conditions without weakening the single-rule classification guard.

### Evidence that would falsify this recommendation

- Implementing A/C for git forces matcher growth into a general query language to remain honest for K8s/NATS/HTTP-spec forms.
- Preserving opaque data breaks the existing S3 baseline or provenance guarantees.
- Even git projection requires procedural logic that declarative predicates cannot express safely.
- A small normalization IR (E) covers the representative set with less surface and clearer safety than field matching.
- Per-extension adapters (B) prove necessary for the first real success, not merely convenient later.

### Source_control access → PADE capability (policy question)

For Experiment 006’s `access: [fetch, pull, push]` with `provider: github`:

- RC does not define PADE capabilities or combined-authority rules.
- The next experiment must **choose and document** a provisional PADE policy reading (independent vs combined)—see §8.
- Suggested provisional choice for the first executable test: **independent translations** with coalescing — `fetch` and/or `pull` → `github.repo.read`; `push` → `github.repo.write`; emit both when both classes are present. Treat any “write implies read” collapse as a separate, explicit policy decision if later desired—not as an RC fact.

### Proposed Experiment 008

**Question:**

> Can `rc-pade` project the real composed rc-demos `source_control`/`git` condition into **multiple** PADE GitHub capability intents from **one** unambiguous classifying rule—using a small generic field-matcher (`equals` / `contains` / AND) over preserved opaque interface data—while keeping HTTP and Google Analytics as explicit `outsidePADE`, preserving fail-closed unknowns, keeping the “exactly one top-level rule matches” classification guard, avoiding condition-name hardcoding and RC implementation imports, and remaining plausible when the same matcher vocabulary is sketched against S3, HTTP, Kubernetes, and NATS?

**Must:**

- Consume the real composed rc-demos Profile (same pins/approach as 006).
- Preserve fail-closed behavior.
- Preserve explicit `outsidePADE` classification.
- Preserve **exactly one** top-level classifying rule per condition (ambiguous multi-rule classification remains an error).
- Support **zero or more** explicit capability projections **within** that single classification (for git: at least read and write from one `access` list under Reading 1).
- Avoid condition-name hardcoding.
- Avoid importing Runtime Conditions implementation code.
- Keep the initial matcher vocabulary to evidence-justified primitives only (`equals`, `contains`, AND)—do not add `containsAll` unless the experiment proves the AND-of-`contains` form inadequate.
- Avoid building a general-purpose expression language unless the experiment itself proves the tiny vocabulary insufficient.
- Avoid solving packaging or Dev Container installation.
- Document the provisional access→capability mapping as PADE policy (Reading 1 preferred for the first test).
- Do not settle permanent YAML syntax; do settle the cardinality requirement above.

**Must not:** declare permanent architecture; solve extension resolution; implement Option D/E/B unless 008 falsifies A/C; allow multiple top-level rules to match one condition as the multi-capability mechanism.

**Success signal:** generate a `DevelopmentSession` whose capabilities reflect the chosen git policy mapping from the live Profile (including **both** read and write when `[fetch, pull, push]` is present under Reading 1), with HTTP/Analytics emitting none, without weakening unknown fail-closed or single-rule classification.

**Failure / learn signal (still valuable):** matcher vocabulary insufficient; opaque preserve insufficient; intra-rule multi-projection proves unworkable; or evidence redirects to B/E.

---

## Appendix: current vs desired conceptual flow

```text
Today (post-006):
  Profile YAML
    → typed RCInterface (drops access/provider/…)
    → match kind+interfaceType
    → require operations[].name
    → DevelopmentSession or explicit error

Hypothesis to test (008):
  Profile YAML
    → core fields + opaque extension interface data
    → exactly one classifying rule (kind+interfaceType; + later extensionId)
    → outsidePADE | zero or more intra-rule field-predicate projections → capabilities
    → DevelopmentSession or fail closed
```
