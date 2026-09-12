# rc-pade

`rc-pade` is an experimental adapter that projects [Runtime Conditions](https://runtimeconditions.github.io/) demand into [PADE](https://github.com/After-Certainty/pade) `DevelopmentSession` intent.

The experiment tests one architectural seam:

```text
application source
      ↓
Runtime Conditions profiler
      ↓
RuntimeConditionsProfile
      ↓
rc-pade + operator mapping policy
      ↓
PADE DevelopmentSession
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

```bash
go run ./cmd/rc-pade generate \
  --profile examples/s3-put-object/runtime-conditions.yaml \
  --policy examples/s3-put-object/policy.yaml
```

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

## Why a separate adapter?

Runtime Conditions describes what a workload requires. PADE describes development-session authority/material intent. The mapping between those models is environment and operator policy, not a semantic that either upstream project needs to own.

Keeping that opinion here lets both contracts evolve independently and makes the interoperability claim testable: an independent implementation can compose the two published formats without importing either codebase.

## Status

Very early experiment. The policy format (`rc-pade.local/v1alpha1`) is local to this repository and deliberately provisional.
