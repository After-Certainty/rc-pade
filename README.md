# rc-pade

`rc-pade` is an experimental adapter that projects [Runtime Conditions](https://runtimeconditions.github.io/) demand into [PADE](https://github.com/After-Certainty/pade) `DevelopmentSession` intent.

The current boundary is:

```text
application source
      ↓
Runtime Conditions profiler / composition
      ↓
RuntimeConditionsProfile
      ↓
Runtime Conditions validation / trusted handoff
      ↓
verified Profile bytes
      ↓
rc-pade + operator mapping policy
      ↓
PADE DevelopmentSession / Consumer bindings
      ↓
PADE consumer / broker / provider
```

Neither side imports the other's implementation. `rc-pade` reads and writes their wire formats.

## Initial experiment

The first fixture projects a Runtime Conditions S3 requirement:

```yaml
kind: aws.s3
interface:
  type: bucket
  operations:
    - name: PutObject
```

through an explicit operator policy:

```yaml
apiVersion: rc-pade.local/v1alpha1
kind: ProjectionPolicy
rules:
  - match:
      kind: aws.s3
      interfaceType: bucket
    operations:
      PutObject:
        capability: aws.s3.bucket.write
        access: write
```

into PADE intent:

```yaml
apiVersion: pade.local/v1alpha1
kind: DevelopmentSession
metadata:
  name: s3-put-object
spec:
  capabilities:
    aws.s3.bucket.write:
      access: write
      required: true
```

The real generated fixture also carries source-profile/workload provenance as annotations.

## Run it

Generate portable PADE session intent from a Profile:

```bash
go run ./cmd/rc-pade generate \
  --profile examples/s3-put-object/runtime-conditions.yaml \
  --policy examples/s3-put-object/policy.yaml
```

After an external Runtime Conditions trust/validation gate has accepted exact
Profile bytes, generate fail-closed PADE Consumer bindings without passing
validator-specific evidence into rc-pade:

```bash
go run ./cmd/rc-pade bind \
  --verified-profile /path/to/verified-profile.yaml \
  --policy /path/to/policy.yaml \
  --broker-binding /path/to/broker.json \
  --allow-capabilities github.repo.read,github.repo.write \
  --output /absolute/path/to/bindings.yaml
```

The `bind` command does not validate Runtime Conditions and does not accept a
validator module, validation report, signing format, or trust key. Its
`--verified-profile` input is an explicit precondition supplied by the caller's
trust boundary. See [Verified Profile → PADE bindings boundary](docs/verified-profile-bindings.md).

Or with [mise](https://mise.jdx.dev/):

```bash
mise run test
mise run demo
mise run check-demo
```

## Experiment rules

This repository intentionally keeps the first version narrow:

- RC conditions are **demand**, not grants.
- Projection policy owns the opinionated translation from RC semantics to opaque PADE capability names.
- A generated `DevelopmentSession` remains an untrusted request. PADE broker/provider policy still decides what authority, if any, is fulfilled.
- `optional: true` on an RC condition becomes `required: false` in the projected PADE capability.
- Unmapped conditions or operations fail closed rather than silently dropping authority requirements.
- The adapter does not infer credentials, AWS account, Region, bucket identity, IAM actions, environment variables, or a provider binding.
- The adapter does not provision resources.
- Runtime Conditions validation and handoff trust remain outside the platform-support projection boundary.

## Why a separate adapter?

Runtime Conditions describes what a workload requires. PADE describes development-session authority/material intent. The mapping between those models is environment and operator policy, not a semantic that either upstream project needs to own.

Keeping that opinion here lets both contracts evolve independently and makes the interoperability claim testable: an independent implementation can compose the two published formats without importing either codebase.

## Status

Very early experiment. The policy format (`rc-pade.local/v1alpha1`) is local to this repository and deliberately provisional.

Interoperability proofs live under [`experiments/`](experiments/), from minimal RC→session fixtures through Coder/GCE identity (005C), composed rc-demos Profile consumption (006), and broker-mediated AWS S3 fulfillment (007). See the [experiment index](experiments/README.md). Experiments 013 and 014 established durable fresh-workspace delivery and signed validation handoff. Experiment 015 dogfoods the reusable `bind` command through `pade-coder/modules/rc-pade-bindings`, closing the active 011/report compatibility seam while preserving 011–014 as historical evidence.

## Security boundary

Projection requests authority; it does not grant it. Operator projection policies
reject unknown fields, while Profiles retain extension-defined data and need a
separate Runtime Conditions validation/trust gate. The `bind` command starts by
revoking the target bindings file to an empty capability map and leaves it empty
on any later failure. See [security boundaries and the policy-decoding
regression](docs/security-boundaries.md) and [Verified Profile → PADE bindings
boundary](docs/verified-profile-bindings.md).
