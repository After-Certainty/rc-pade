# Projection security boundary investigation

Inspected `main` at `704774807124748a24b1d5401686239d26165139` on 2026-10-09.
Related cross-repository report: PADE `docs/security/2026-10-boundary-investigation.md`.

## Confirmed deficiency: unknown policy fields silently removed guards

`cmd/rc-pade/main.go:readYAML` originally used non-strict YAML unmarshalling for
both profiles and operator policy. A misspelled `cover` was silently ignored,
allowing `[fetch, admin]` to project the recognized read demand without checking
that `admin` was accounted for. A misspelled `when` could make a clause
unconditional; a misspelled `require` could remove its guard. This violates the
operator's intended fail-closed projection boundary. It does not bypass PADE
broker authorization: projection still produces requests, not grants.

The regression tests in `cmd/rc-pade/main_test.go` failed on the inspected source
for `coverTypo`, `requireTypo`, `whenTypo`, and a trailing YAML document. The fix
uses `yaml.Decoder.KnownFields(true)` for **operator policy only**, and requires
exactly one document. No dependencies or vocabulary are added.

Compatibility: valid existing policies retain their meaning. Unknown policy keys
(previously silently ignored), concatenated documents, and malformed files now
fail. Comments remain legal. Profiles retain extension-owned opaque interface
fields, with validation delegated to Runtime Conditions. The positive test also
shows `[fetch, admin]` fails against the valid policy and returns no session.
Run `go test ./... -count=1`; the updated suite passes.

## Boundaries preserved

- RC requirements and `workload.uri` are untrusted demand/provenance, not
  authenticated workload identity.
- Production `generate` does not prove RC validation occurred. Experiment 009's
  validator and byte-hash continuity are a separately composed pipeline gate.
- Recognized conditions must match one rule; unknown operations, covered access
  values, conflicts and ambiguous rules fail. `cover` remains an operator choice,
  not an automatic interpretation of every extension field.
- `outsidePADE` explicitly emits no capability; it neither grants nor denies
  resource access in some other system.
- Capability names request issuance. PADE broker policy owns authorization;
  providers materialize; downstream IAM owns use of resulting credentials.
- Coder workspace owners and RC provenance are not substituted for GCE/Cursor
  token subjects. Equivalent names across runtimes do not create equivalent IAM.
- Experiment 010's visible-vocabulary conclusion stands. No extension-ID dispatch,
  validation attestation, vendor logic in PADE, or upstream RC changes were added.

No production broker, cloud identity endpoint, or live downstream account was
contacted. Historical experiment results were reviewed, not claimed as rerun.
