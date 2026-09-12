# Experiment 003 — source to session

## Question

Can unchanged application source produce PADE `DevelopmentSession` intent without a human authoring an intermediate Runtime Conditions profile?

## Chain under test

```text
ordinary boto3 source
        ↓
Runtime Conditions Python profiler + SDK mappings
        ↓
generated RuntimeConditionsProfile
        ↓
rc-pade + existing projection policy
        ↓
generated PADE DevelopmentSession
```

This experiment deliberately reuses Runtime Conditions' own proven AWS Python maintenance/profiler path rather than reproducing its SDK packaging logic inside `rc-pade`.

## Pinned upstream proof tuple

The pins in `provenance.yaml` match a Runtime Conditions evidence run that successfully rebuilt mapped boto3/botocore/s3transfer wheels, installed the real Python profiler, generated profiles for all seven AWS fixtures, and semantically matched the accepted direct-client profile.

The direct-client source vendored under `app/storage.py` is only here for inspection and byte comparison. The actual run profiles the source from the pinned upstream checkout.

## Run

```sh
bash experiments/003-source-to-session/run.sh
```

Set `RC_PADE_EXPERIMENT_WORK` to choose the work directory. By default the script uses `.work/experiment-003`.

The run produces:

- `generated-runtime-conditions.yaml`
- `generated-pade.yaml`
- `rc-maintenance/` containing the upstream RC maintenance evidence for this run

## Acceptance criteria

- The application source is unchanged ordinary boto3 code.
- The source used by the profiler is byte-identical to the pinned fixture recorded here.
- The real Runtime Conditions Python profiler generates the profile.
- The generated profile resolves the S3 bucket `PutObject` requirement proven in Experiment 002.
- `rc-pade` uses the existing `examples/s3-put-object/policy.yaml`; no S3 semantics are added to the adapter implementation.
- The resulting PADE document exactly matches Experiment 002's expected `DevelopmentSession`.
- The chain does not invent an AWS account, Region, bucket identity, IAM action, credential value, environment-variable convention, or PADE provider binding.

## Boundary

This is still a generation/interoperability experiment. It does not provision an S3 bucket and it does not ask PADE to fulfill the capability. A later experiment can place the generated session inside an actual developer workspace and exercise identity-aware fulfillment.
