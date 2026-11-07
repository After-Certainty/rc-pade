# Experiment 013 fixtures — trusted input pins

These files are the operator-/pipeline-pinned bytes embedded into the
`gcp-pade` Coder template for durable delivery on a fresh workspace.

| File | Role | SHA-256 |
|---|---|---|
| `profile.yaml` | Experiment 011 Checkpoint B Case A composed Profile | `53fe0bca5664c9b889304c881d6643cec163f449a9d02a91fd5a6d635ad62e19` |
| `validation-report.yaml` | Projected adapter-shaped validation evidence | `aceb19dc7cc6717aa962fa088192388731a88e60f262e3a6a2264fa00dedb20f` |
| `policy.yaml` | Operator projection policy (`experiments/008-rc-field-projection/policy.yaml`) | `a5f8f138e2ed5ca2d559d8711d7de50fadb0288c5c02532f8316c239a23007a4` |
| `allow-capabilities.txt` | Operator allowlist | `152d75d84cfffb6aa04e21658ae207a7dd4c092a0f2e4d2a762e784ba71b009c` |

The Experiment 011 adapter is **not** stored in this git tree. At workspace
startup the Coder template fetches the public `rc-pade` archive at a pinned
commit and builds `experiments/011-coder-rc-bindings` with a pinned Go
toolchain (Coder's template archive limit is 1MiB). Broker binding is **not**
embedded; it continues to come only from `module.pade.broker_binding`.

See `SOURCE.txt` for the exact pins recorded into the template.
