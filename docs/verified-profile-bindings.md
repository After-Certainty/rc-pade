# Verified Profile → PADE bindings boundary

Experiments 011–014 established two different responsibilities that should not
be coupled in one adapter contract:

1. **Runtime Conditions trust / validation** decides whether exact Profile bytes
   are accepted.
2. **Platform support / PADE binding** interprets those already-accepted bytes
   under operator policy.

The reusable `rc-pade bind` command implements only the second responsibility.

```text
Runtime Conditions producer / validator
        ↓
trusted handoff verification
        ↓
verified Profile bytes
        ↓
rc-pade bind
  + ProjectionPolicy
  + capability allowlist
  + PADE broker binding
        ↓
PADE Consumer bindings
  + optional DevelopmentSession
```

## Command contract

```bash
rc-pade bind \
  --verified-profile /path/to/verified-profile.yaml \
  --policy /path/to/policy.yaml \
  --broker-binding /path/to/broker.json \
  --allow-capabilities github.repo.read,github.repo.write \
  --output /absolute/path/to/bindings.yaml \
  --session-out /absolute/path/to/development-session.yaml
```

`--session-out` is optional. The bindings output path is required and must be
absolute.

The command intentionally does **not** accept:

- an RC validator module or version;
- `accepted: true` evidence;
- per-condition validation results;
- a validation-report schema;
- a signing format or trust key.

Those belong to the upstream trust/validation boundary. The
`--verified-profile` name is an explicit precondition: callers must not pass
untrusted Profile bytes directly.

## Fail-closed behavior

Once an absolute bindings target is known, `bind` first replaces it with:

```yaml
version: "0.1"
capabilities: {}
```

Any later failure leaves that empty configuration in place, including:

- missing or malformed verified Profile input;
- unsupported Runtime Conditions demand;
- malformed or misspelled operator policy;
- projected capability outside the operator allowlist;
- invalid broker-only configuration;
- invalid session output;
- session write failure.

The optional DevelopmentSession is written before capability bindings are
activated.

## Relationship to the experiments

Experiment 011 remains unchanged as historical evidence. Its experiment-local
adapter required a validator-specific `validation-report.yaml` because that
was the trust shape under test at the time.

Experiment 014 later proved that signed handoff verification can establish
trust before platform support evaluation, while also exposing the old report as
a compatibility dependency rather than the actual trust root.

`rc-pade bind` is the cleanup from that finding: active platform binding no
longer depends on which Runtime Conditions validator produced or verified the
Profile.

This does not standardize the Experiment 014 signing format, key lifecycle, or
validation provenance model. It only keeps those concerns outside rc-pade's
platform-support boundary.
