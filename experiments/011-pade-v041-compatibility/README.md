# Experiment 011 — PADE v0.4.1 release compatibility

**Question:** Can the **released PADE v0.4.1 CLI** still consume the
`DevelopmentSession` manifests produced by `rc-pade`, without changing
historical Runtime Conditions inputs or original experiment evidence?

## Provenance

- Release: [PADE v0.4.1](https://github.com/After-Certainty/pade/releases/tag/v0.4.1)
- Source commit: `05fb0361c8af17c2031b2e3815d252d9cc49bdf7`
- Release archives: hard-pinned SHA-256 values in `run.sh` and `provenance.yaml`
- Toolchain: Go 1.26.10 from root `mise.toml` / GitHub Actions
- Inputs: original S3 fixture and pinned Experiment 002 real RC profile; unchanged policy and expected manifests
- Broker: **not contacted**; no cloud credentials or binding used

## Run

From repository root:

```bash
mise run 011:compat
# or
bash experiments/011-pade-v041-compatibility/run.sh
```

Requires Go, Python 3, curl, tar, and SHA-256 utilities. Linux amd64, Linux arm64 and macOS arm64 supported. Set `RC_PADE_011_WORK` to select an output directory; by default output is saved under gitignored `experiments/011-pade-v041-compatibility/generated/`.

## Assertions

For **both** profiles:

1. Download the v0.4.1 binary and verify a separately hard-pinned SHA-256.
2. Check the official CLI's version and source commit.
3. Generate the new `DevelopmentSession` with the current projector.
4. Diff against the original expected YAML **byte-for-byte**.
5. Invoke `pade validate` and `pade --json plan` with user bindings disabled.
6. Assert exactly one `aws.s3.bucket.write` capability, `access: write`, `required: true`, `bound: false`, `status: unbound`.

The CI workflow uploads non-secret manifests, validation output, JSON plans and local run provenance.

## Limits and historical integrity

This is an **offline CLI wire-format compatibility** result. It does not prove live broker authorization, GCE/Cursor workload authentication, credential fulfillment, or AWS S3 PutObject. Live behavior requires a separately authorized check from the actual GCE workspace.

Experiments 004, 005C and 007 retain the PADE versions they originally tested. A later v0.4.1 live smoke should be recorded as **new, dated, append-only** evidence, not edits to earlier observations.
