# Experiment 005C — Deployed PADE multi-issuer fulfillment

## Question

Can this GCE-backed Coder workspace act as a real PADE consumer against the **deployed** multi-issuer PADE broker—using GCE metadata identity only—to obtain broker-derived GitHub Material and succeed at a read-only GitHub API call?

## Sequence context

| Experiment | Proved |
|------------|--------|
| [005A](../005-coder-identity-discovery/) | Local Coder (Docker/LinuxKit) exposed **no** PADE-fit workload identity |
| [005B](../005b-gcp-workload-identity/) | GCE metadata can mint short-lived, audience-bound Google ID tokens that fit PADE’s `TokenSource` / broker verify model |
| **005C (this)** | PADE v0.3.0 GCE TokenSource + deployed Cloud Run broker + least-privileged Google subject → real `github.repo.read` Material |

005C is the final **identity / fulfillment substrate** experiment for this workspace. It does **not** complete the full RC → rc-pade → PADE vertical slice (see [What 005C did not prove](#what-005c-did-not-prove)).

## Architectural result

```text
Coder owns workspace lifecycle.
GCP / GCE owns workload identity.
PADE consumes that identity and fulfills authorized Material.
```

Proven path:

```text
real GCE metadata identity
      ↓
PADE v0.3.0 GCE TokenSource
      ↓
deployed Cloud Run PADE broker
      ↓
Google issuer selected
      ↓
issuer alias + subject authorization
      ↓
github.repo.read
      ↓
broker-side GitHub provider
      ↓
derived GitHub Material
      ↓
ordinary child process
      ↓
real GitHub read succeeds
```

## Boundary

This experiment validates environment + identity + broker trust + authorization + materialization.

It does **not**:

- change Runtime Conditions semantics
- change rc-pade projection logic
- design the next RC → DevelopmentSession → fulfillment integration experiment
- grant the GCE subject capabilities beyond the configured least privilege
- print JWTs or GitHub tokens
- add durable credentials to the Coder workspace
- treat Coder as an identity provider

PADE implementation details (TokenSource internals, multi-issuer verifier design) live in [After-Certainty/pade](https://github.com/After-Certainty/pade). This document only records what the **rc-pade / Coder / GCE** experiment boundary observed.

## Environment

Manual validation from Coder workspace `pade-gcp` on GCE (same class of workspace as 005B).

| Fact | Observation |
|------|-------------|
| GCP project | `after-certainty` |
| Zone | `us-central1-a` |
| Attached service account | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` |
| Durable ADC / SA JSON keys | **absent** (not required) |
| Identity provider | Google / GCE metadata — **not** Coder |

## PADE substrate (summary)

PADE **v0.3.0** shipped the pieces this proof depends on (implemented and released in the PADE repo):

- GCE TokenSource
- Consumer `broker.identity: gce`
- Multi-issuer broker verification with static trusted issuers
- Authorization by `(issuer alias, subject)`
- Verified issuer context propagation
- Backward-compatible Cursor identity behavior

The production broker was upgraded to v0.3.0 as **one** Cloud Run process trusting:

```text
cursor → https://api.cursor.com
google → https://accounts.google.com
```

The allowlisted Google workload subject for this workspace was authorized only for:

```text
github.repo.read
```

## Deployed broker

```text
https://pade-broker-754719312452.us-central1.run.app
```

Temporary Consumer binding used for validation (not committed as a permanent example):

```yaml
version: "0.1"

capabilities:
  github.repo.read:
    provider: broker
    broker:
      endpoint: https://pade-broker-754719312452.us-central1.run.app
      audience: https://pade-broker-754719312452.us-central1.run.app
      identity: gce
```

## How the validation was run

1. Download the official PADE **v0.3.0** Linux amd64 release binary (not an older local pin).
2. Confirm GCE metadata can mint an audience-bound ID token for the deployed broker URL (safe claims only; raw JWT never printed).
3. `pade exec` with the temporary binding and capability `github.repo.read`.
4. In the child: assert `GITHUB_TOKEN` is non-empty **without printing it**; `GET` `https://api.github.com/repos/After-Certainty/after-certainty`; assert repository identity; print only the success line below.

Re-running requires the same GCE-attached workspace, network access to the deployed broker and GitHub, and the allowlisted subject still authorized for `github.repo.read`. This is a **manual** production-path check, not CI.

## Safe evidence observed

PADE CLI:

```text
pade version v0.3.0 (0467ed2, built 2026-09-13T02:26:11Z)
```

GCE identity (claims summary only):

```text
metadata identity HTTP 200
iss=https://accounts.google.com
aud=<deployed Cloud Run broker URL>
sub_length=21
email=pade-coder-workspace@after-certainty.iam.gserviceaccount.com
TTL=3600s
RS256
```

The numeric Google subject is intentionally omitted from this document; it is configured in broker policy, not published here.

Child / Material proof:

```text
repo_full_name=After-Certainty/after-certainty
repo_name=after-certainty
deployed-gce-broker: success
```

Notes:

- One broker served both Cursor and Google issuers; this run exercised the **Google / GCE** path.
- No durable credentials were added to the workspace for the proof.
- No JWT or GitHub token was printed.
- Cursor remains a separate issuer; existing Cursor behavior stays backward compatible (not re-proven in this workspace).

## What 005C proved

- This GCE-backed Coder workspace is a **valid PADE consumer environment** against the real deployed broker.
- Workload identity comes from **GCE metadata**, selected via `broker.identity: gce`.
- The deployed broker selects the **Google** issuer, authorizes by issuer alias + subject, and returns `github.repo.read` Material usable by an ordinary child process.
- Least privilege held: only `github.repo.read` was granted to the GCE subject for this validation.

## What 005C did not prove

```text
ordinary source
      ↓
Runtime Conditions profiler
      ↓
RC Profile
      ↓
rc-pade translation
      ↓
generated PADE DevelopmentSession
      ↓
PADE Consumer
      ↓
deployed broker fulfillment
      ↓
downstream application succeeds
```

That full vertical slice remains a **later** rc-pade experiment. 005C only establishes the identity, broker trust, authorization, and materialization **substrate** that experiment can assume.

## Result

```text
Result: GCE-backed Coder + PADE v0.3.0 + deployed multi-issuer broker
successfully fulfilled github.repo.read for the allowlisted Google subject.

Coder was not the identity provider.
No durable workspace credentials were required.
JWT and GitHub token values were never printed.

Next rc-pade work can use this deployed fulfillment path as already validated,
and focus on Runtime Conditions → rc-pade → DevelopmentSession → broker.
```

## Recommended next experiment

Focus on the integration seam only:

```text
Runtime Conditions
      ↓
rc-pade
      ↓
PADE DevelopmentSession
      ↓
existing deployed PADE fulfillment path
```

Do not re-prove GCE workload identity or multi-issuer broker trust unless those layers change.

## Safety notes

- Do not commit raw JWTs, GitHub tokens, SA keys, or `CODER_AGENT_TOKEN` values.
- Do not publish the numeric Google `sub` in public experiment docs unless there is a clear need.
- Broker URL and service-account **email** are operational identifiers used here for reproducibility; they are not secrets.
- Prefer temporary bindings for production-broker checks over committing live production endpoints as permanent examples unless the repository deliberately adopts that pattern later.
