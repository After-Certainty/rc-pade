# Experiment 002 — real Runtime Conditions S3 profile

## Question

Can `rc-pade` consume a Runtime Conditions profile produced by the current RC SDK/profiler work, without either implementation knowing about the other, and derive the same PADE `DevelopmentSession` intent proved by Experiment 001?

## Pinned upstream evidence

This experiment uses Runtime Conditions' AWS Python S3 direct-client fixture pinned at:

`runtimeconditions/sdk-authorship-discovery@d89c75ee49145277158d8d4e29383d10cca8d1f3`

Application source:

`s3/python/direct-client/src/s3_direct_client/storage.py`

Source blob:

`81c18cc1a076b5a1f2968fe56a2efd4ef9c5d105`

The application uses ordinary boto3:

```python
client = boto3.client("s3")
client.put_object(Bucket=bucket, Key=key, Body=source.read_bytes())
```

Generated Runtime Conditions profile upstream:

`authorship/aws-python/results/profiles/direct-client.yaml`

Profile blob:

`05c21059412a636b0364edd1ffb512ced9e670b0`

The exact generated profile is vendored in this directory as `runtime-conditions.yaml`. Machine-readable upstream provenance is recorded in `provenance.yaml`.

Its relevant condition is:

```yaml
kind: aws.s3
interface:
  type: bucket
  operations:
    - name: PutObject
```

## Proven chain

```text
ordinary boto3 source
        ↓
Runtime Conditions profiler + SDK mappings
        ↓
real RuntimeConditionsProfile
        ↓
rc-pade + existing projection policy
        ↓
PADE DevelopmentSession
```

The projection deliberately reuses `examples/s3-put-object/policy.yaml`. No experiment-specific authority mapping is added for the real RC fixture.

Run the proof locally with:

```bash
go run ./cmd/rc-pade generate \
  --profile experiments/002-real-rc-profile/runtime-conditions.yaml \
  --policy examples/s3-put-object/policy.yaml \
  | diff -u experiments/002-real-rc-profile/expected-pade.yaml -
```

CI runs the same assertion.

## Result

The real RC-generated S3 requirement projects to:

```yaml
spec:
  capabilities:
    aws.s3.bucket.write:
      access: write
      required: true
```

The generated `DevelopmentSession` also preserves the RC profile name and workload URI/version as provenance annotations. It does not infer an AWS account, Region, bucket identity, credentials, IAM actions, environment variables, or provider binding.

## Acceptance criteria

- [x] The RC input is a real upstream generated profile, not an RC condition authored specifically for `rc-pade`.
- [x] `rc-pade` imports neither Runtime Conditions profiler internals nor PADE internals.
- [x] The `aws.s3` bucket `PutObject` requirement projects to the existing opaque PADE capability `aws.s3.bucket.write` through adapter policy.
- [x] The output remains `pade.local/v1alpha1` `DevelopmentSession` intent.
- [x] The adapter does not invent an AWS account, Region, bucket identity, credentials, IAM actions, environment variables, or provider binding.
- [x] RC demand remains an untrusted request; PADE authorization/fulfillment remains downstream.
- [x] CI covers the pinned real-profile projection.

## Next experiment

The stronger proof is to regenerate the profile from the ordinary boto3 source during the experiment itself using the RC profiler and SDK mappings, then pipe that generated profile directly into `rc-pade`. That step is intentionally separate so this compatibility fixture remains deterministic and does not depend on network availability or movement of upstream `main`.
