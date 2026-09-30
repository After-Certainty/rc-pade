# Experiment 009 — upstream RC validation as a gate before rc-pade

**Status: hypothesis supported for cases A–D. Production rc-pade changed by zero lines (`cmd/`, `internal/`, root `go.mod`/`go.sum`, `examples/` untouched).**

## Question

Can the current upstream Runtime Conditions resolver/validator run as a pipeline gate in front of an **unchanged** `rc-pade`, and does placing it there cleanly separate **RC semantic validity** from **platform capability support**?

Scope is deliberately narrow: cases A–D only. Ambiguous-kind resolution, explicit `conditions[].extension` selectors, cross-Profile semantic substitution, and supported-extension identity gating are **not** tested here (see [Deferred to Experiment 010](#deferred-to-experiment-010)).

## Starting point

At the Experiment 008 pins nothing in the chain resolved extensions or validated the Profile:

- rc-demos `13a85bd` composes the Profile and dedupes `extensions[]` strings; it does not load extensions or apply schemas. (Upstream rc-demos added `profile-validate` after that commit.)
- `rc-pade` parses the Profile non-strictly and checks only `apiVersion`/`kind`, `interface.type`, and optional `operations`. It drops `extensions[]` and `conditions[].extension`.

Experiment 008 therefore consumed a **raw Profile with minimal core-shape checks**. Its "unknown access fails closed" result came from rc-pade `cover` policy, not from RC validation.

## Pipeline

```text
rc-demos compose (008 pins, unchanged)
        ↓
dev-container.profile.yaml ──────────────┐  (sha256 recorded)
        ↓                                │
rcvalidate  (experiment-local wrapper    │
             over rc-extension-resolver) │
        ↓ exit 0 only                    │  identical bytes
rc-pade generate (unchanged) ◄───────────┘  (sha256 re-checked before and after)
        ↓
DevelopmentSession, or explicit failure
```

```sh
bash experiments/009-rc-validated-projection/run.sh
```

The harness deletes any previous `generated/` and work tree, clones pinned siblings into a disposable work tree, composes the real Profile, builds `rc-pade` from this checkout and `rcvalidate` from [`rcvalidate/`](rcvalidate/), runs every case, and writes evidence to gitignored `generated/`. It exits non-zero if any assertion fails. `rcvalidate` builds with Go 1.27.1; the harness sets `GOTOOLCHAIN=auto` for it so the Go toolchain can switch automatically.

| Variable | Default |
|----------|---------|
| `RC_DEMOS_REPO` / `RC_DEMOS_REF` | `ksteffe/rc-demos` @ `13a85bd…` (same as 008) |
| `EXTENSIONS_REPO` / `EXTENSIONS_REF` | `runtimeconditions/extensions` @ `7a08c8b…` |
| `PROFILER_REPO` / `PROFILER_REF` | `runtimeconditions/go-rc-profiler` @ `5d2e860…` |
| `RC_PADE_EXPERIMENT_WORK` | `.work/experiment-009` |
| `RC_PADE_KEEP_WORK` | `0` (set `1` to keep the work tree) |

Gate rules in the harness:

- `rcvalidate` exits `0` (accepted), `1` (rejected by the resolver), or `2` (could not validate, for example an extension file unavailable to the harness). Only `0` opens the gate.
- rc-pade is invoked only if the SHA-256 of the file about to be projected equals the SHA-256 `rcvalidate` reported for the bytes it accepted; otherwise the case records `projection.skipped`.

### The validator used

`rcvalidate` is a thin wrapper (its own Go module, Go 1.27, never imported by rc-pade) around [`runtimeconditions/rc-extension-resolver`](https://github.com/runtimeconditions/rc-extension-resolver) at `91c46bf6bcc8` (`v0.0.0-20260929185940-91c46bf6bcc8`). This is the **current upstream implementation** used by this experiment. It is **not** claimed to be a fully conformant sixth-draft validator.

What it checks (and what "accepted" means in this experiment):

- resolves every declared extension and its dependencies; rejects dependency cycles and a definition whose non-empty `metadata.id` differs from its URI
- merges them, rejecting conflicting interface-type or schema owners
- per Condition: `kind` and `interface.type` are known, and at least one schema is bound to `(kind, interfaceType)`
- per Condition: every extension JSON Schema bound to its `(kind, interfaceType)` passes

What it does not check (so this experiment does not claim it):

- that `extensions[]` declares its full dependency closure
- interface/condition field vocabulary or field values beyond what the schemas enforce
- unscoped schemas (for example env-configuration `configuration-shape`), which it skips
- it has no Profile-level API or CLI

Wrapper-only pieces:

- **File loader.** Extension identifier URIs currently return 404, so the four declared URIs are mapped to files in the pinned `runtimeconditions/extensions` checkout. This is transport; resolution stays upstream.
- **`resolveAll`.** Copied (with attribution) from `runtimeconditions/rc-admission-webhook@91e97af`, because the resolver library resolves one root at a time.
- **Report.** `validation-report.yaml` records resolver version, Profile SHA-256, resolved extensions, and per-Condition validity and errors.

The Profile is never rewritten or normalized. rc-pade receives the same file path whose bytes the validator hashed.

## Results

| Case | Input | Validation | rc-pade |
|------|-------|------------|---------|
| A | real composed Profile, 008 policy | accepted (3/3) | `github.repo.read` + `github.repo.write` |
| B | `access: [fetch, admin]`, 008 policy | **rejected** (schema enum) | not invoked |
| C | `access: [clone]`, `policy-no-clone.yaml` | accepted (3/3) | **fails**; no session |
| D | `api/http`, `google.analytics/web` (in A) | accepted | explicit `outsidePADE`; no capabilities |

69 assertions, 0 failures. In the recorded run, the composed Profile SHA-256 (`53fe0bca…2e19`) equalled the Profile composed by the Experiment 008 harness in the same workspace, and the same hash is recorded before validation, after validation, immediately before rc-pade, and after rc-pade in cases A and C.

Observed evidence:

- **B validator:** `[source-control-git] /interface/access/1/enum: Value admin should be one of the allowed values: clone, fetch, pull, push`
- **B bypass** (gate skipped deliberately, evidence only): rc-pade still fails closed — `cover interface.access: value "admin" is not accounted for by any satisfied project clause`
- **C rc-pade:** `cover interface.access: value "clone" is not accounted for by any satisfied project clause`; exit 1, empty stdout, no session
- **A session:**

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

Case B and C Profiles are derived from the composed Profile by a scripted mutation that changes only `application-source` `interface.access`; the tool re-reads its output and fails if anything else changed.

## Four layers, kept separate

1. **RC semantic validity** — decided by the upstream resolver. Case B (`admin`) is not a Runtime Conditions value for `source_control/git` and is rejected before rc-pade runs.
2. **Platform capability support** — decided by operator policy. Case C (`clone`) is a valid RC value, but this platform's policy does not support it, so projection fails closed. RC-valid does not mean supported.
3. **PADE projection policy** — cases A and D. The unchanged 008 policy maps `fetch`/`pull` → `github.repo.read`, `push` → `github.repo.write`, and classifies HTTP and Google Analytics as explicitly `outsidePADE`.
4. **Resource binding / fulfillment** — not exercised. See the invariant below.

### Resource-binding invariant

`workload.uri` (and the `source-workload-uri` annotation) is workload identity/provenance and may itself be a GitHub URL. That is allowed. What the assertions check is that no **target-resource binding** is introduced:

- no Condition in any case Profile carries a repository/URL/target/binding/credential/token/account/bucket/endpoint/fulfillment key, and the `source_control` interface has exactly `type`, `provider`, `access`
- the session decodes strictly as `apiVersion`/`kind`/`metadata(name, annotations)`/`spec.capabilities(access, required)`: no repository target is bound into any capability
- session annotations are limited to the three workload-provenance keys

No credentials, account identity, bucket binding, token, or fulfillment configuration is introduced anywhere.

## What 009 establishes

- The current upstream resolver can be inserted as an out-of-process gate in front of rc-pade with **zero** production changes, consuming the real composed Profile as-is.
- rc-pade can act on the gated Profile without loading or re-resolving extension artifacts.
- The exact bytes accepted by the gate are the bytes rc-pade projects (SHA-256 chain).
- RC semantic validity (B) and platform capability support (C) are observably different failure points; rc-pade's `cover` remains an independent second line of defense (B bypass).

## What 009 does not establish

- That the Profile is fully sixth-draft valid, or that rc-extension-resolver is a complete RC validator. "Accepted" means only "accepted by rc-extension-resolver@91c46bf".
- That the Experiment 008 matcher or `rc-pade.local/v1alpha1` policy format is final architecture.
- That rc-pade can tell whether its input was validated. Validation is a property of pipeline composition; no wire-level attestation exists and none was invented.
- Anything about ambiguous kinds, selectors, provenance, or extension identity (below).
- Anything about fulfillment, repository binding, credentials, or S3.

## Deferred to Experiment 010

Open questions, recorded from the 009 design investigation. None were tested or solved here.

- **Ambiguous `kind` resolution.** The resolver exposes `KindMatch` (`explicit` / `fallback`) and `ResolvedExtension`; 009 does not exercise or record them.
- **Explicit `conditions[].extension` selectors.** The first-party `source-control-git` and `google-analytics-web` schemas set `additionalProperties: false` at the Condition root and appear to reject the core `extension` field. rc-pade also silently drops that field.
- **Provenance fidelity.** `ResolvedExtension` names the kind owner, while schemas are keyed by `(kind, interfaceType)` and interface-type ownership is not checked against the kind owner; the two could diverge.
- **Cross-Profile semantic substitution.** Could a different extension defining the same `(kind, interfaceType)` project identically in rc-pade?
- **Supported-extension identity gating.** Where would a platform capability catalog keyed on resolved identity live, and which identity would it key on?
- **Validator divergence.** `go-rc-profiler/extensioncheck` checks closure and field vocabulary but rejects ambiguous kinds; rc-extension-resolver allows ambiguous kinds but skips unscoped schemas and does not enforce that a selector appears in `extensions[]`.
- **Upstream integration gaps.** No Profile-level resolver API or CLI; unpublished extension URIs; no wire-level validation attestation.
- **Pin retarget.** When to move rc-demos from the fork pin to upstream `d9c47b7`, which validates during compose.

## Evidence layout (`generated/`)

| Path | Contents |
|------|----------|
| `environment.txt` | rc-pade commit and production-tree cleanliness, sibling commits, validator version/commit, Go versions |
| `profiles/` | composed Profile + provenance, B/C variants, `variants.txt` |
| `cases/<A,B,C>/validation-report.yaml` | resolver verdicts, per-Condition errors, Profile SHA-256 |
| `cases/<A,B,C>/validation.{stdout,stderr,exit}` | gate output |
| `cases/<A,B,C>/profile.sha256.*` | before/after validation, passed to rc-pade, after projection |
| `cases/<A,C>/projection.{stdout,stderr,exit}` | rc-pade output |
| `cases/A/development-session.yaml` | session for the successful case |
| `cases/B/projection.skipped`, `cases/B/bypass/` | gate rejection marker; bypass evidence |
| `assertions.txt`, `results.txt` | per-assertion PASS/FAIL and summary |

## Pins

| Component | Ref |
|-----------|-----|
| rc-demos | `ksteffe/rc-demos` @ `13a85bd4221797c94e209fad576a9d4ab89522f3` (temporary fork pin, same as 006/008) |
| extensions | `7a08c8b9cc298c2c4a84b32d7cad2c3d813f97a7` |
| go-rc-profiler | `5d2e860e48842b89ec83414123a7e59228f61d36` |
| rc-extension-resolver | `91c46bf6bcc8207475ade30a6f6c1d9ab810ac2e` |
| baseline policy | [`../008-rc-field-projection/policy.yaml`](../008-rc-field-projection/policy.yaml) (unchanged) |
| case C policy | [`policy-no-clone.yaml`](policy-no-clone.yaml) (008 policy minus the `clone` clause; `cover` kept) |
