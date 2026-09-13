# Experiment 005 — Coder identity discovery

## Question

What trustworthy workload identity, if any, is actually available to a process running inside this Coder workspace—such that it could satisfy PADE’s `TokenSource` contract?

```go
Token(ctx context.Context, audience string) (Token, error)
```

This experiment gathers evidence only. It does **not** change PADE, add a Coder identity adapter, mint access tokens for display, or attempt capability fulfillment.

## How to re-run

```sh
bash experiments/005-coder-identity-discovery/inspect.sh
```

The script prints safe, shareable evidence and writes the same text to gitignored `generated/safe-evidence.txt`. It never prints bearer tokens, agent tokens, JWTs, cloud credentials, or `coder external-auth access-token` output.

## Environment summary

Evidence collected on branch `experiment/coder-identity-discovery` inside workspace `gold-cuckoo-46` (owner `ksteffe`, agent `main`).

| Fact | Observation |
|------|-------------|
| Host shape | Linux linuxkit / Ubuntu 26.04; `/.dockerenv` present; DMI product `BHYVE` |
| Kubernetes | No `KUBERNETES_SERVICE_*`; no `/var/run/secrets/kubernetes.io/serviceaccount` |
| Cloud CLIs | `aws`, `gcloud`, `az`, `kubectl` absent |
| Cloud workload-identity env | `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, Azure federated token, GCP ADC all absent |
| SPIFFE | No workload API sockets; `SPIFFE_ENDPOINT_SOCKET` absent |
| Cursor Cloud Agent OIDC socket | `CURSOR_AGENT_SOCKET` absent; `/run/cursor/api.sock` absent |
| Cursor UI signal | `CURSOR_AGENT=1` (desktop/remote agent flag), **not** a mintable OIDC socket |
| Coder | CLI v2.35.3 present; `CODER=true`; `CODER_AGENT_TOKEN=present` (value never printed) |
| Coder user session | `coder whoami` fails: not logged in as a user session |
| Link-local metadata IP | Route to `169.254.169.254` exists via Docker bridge; **not** probed over HTTP |

Interpretation: this workspace is a **Docker-based Coder workspace**, accessed through the **Cursor desktop remote UI**. It is not a Kubernetes pod with projected service-account tokens, and it is not a Cursor Cloud Agent VM with `/run/cursor/api.sock`.

## Identity candidates discovered

### 1. `CODER_AGENT_TOKEN` (present)

**What it is:** Environment material used with `CODER_AGENT_AUTH=token` so the workspace **agent** can authenticate to the **Coder control plane** (`CODER_AGENT_URL` present; value not printed).

**What it is not:** An audience-bound OIDC JWT for arbitrary relying parties. There is no evidence it is exchangeable for a PADE-broker audience, verifiable via a public JWKS as workload identity, or intended as a general `TokenSource`.

**Classification: C — identity/material exists but is unsuitable for PADE TokenSource.**

### 2. Coder user session / personal access tokens

CLI exposes `coder login`, `coder whoami`, and `coder tokens` (personal access tokens for automated clients to Coder). In this workspace, `coder whoami` reports **not logged in**.

Even when present, Coder PATs authenticate to the **Coder API**, not to a PADE broker as an audience-bound OIDC assertion.

**Classification: C — unsuitable as PADE workload identity.**

### 3. Coder external-auth access tokens (e.g. GitHub)

`coder external-auth access-token` can print provider tokens for services such as GitHub. Experiment 004 already showed GitHub **read** via this path and **no write** from the workspace (commits were bundled and pushed locally).

These tokens are **capability credentials** (access to GitHub/etc.), not proof of workspace workload identity to a PADE broker.

```text
workload identity  → proves who/what the workspace session is
capability material → lets an authenticated session access GitHub/AWS/etc.
```

**Classification: capability credential — not TokenSource identity.** (Inspection deliberately did not mint or print such tokens.)

### 4. Cursor Cloud Agent OIDC socket

PADE’s current reference TokenSource (`internal/identity/cursor`) mints audience-bound JWTs via:

- `CURSOR_AGENT_SOCKET` or default `/run/cursor/api.sock`
- `POST /v1/tokens/oidc` with `{"aud":"..."}`

Both the env var and socket are **absent** here. `CURSOR_AGENT=1` only indicates the Cursor agent UI connected remotely; it does not expose the Cloud Agent identity API.

**Classification: absent in this environment.**

### 5. Kubernetes projected / audience-bound service-account tokens

No service-account mount, no projected token paths, no `kubectl`.

**Classification: absent.**

### 6. Cloud provider workload identity (IRSA / GKE WI / Azure federated)

No role/web-identity env, no federated token files, no cloud SDKs. A Docker-bridge route to `169.254.169.254` exists but, without AWS identity env or tooling, is treated as inconclusive networking—not authorization to fetch IMDS credentials. This experiment does not probe IMDS.

**Classification: absent (no strong intended workload-identity configuration).**

### 7. SPIFFE / SPIRE Workload API

No sockets or env.

**Classification: absent.**

## Candidate comparison

| Candidate | Short-lived | Audience-bound | Verifiable issuer | Stable subject | Durable secret required in workspace | Fits PADE TokenSource? |
| --------- | ----------- | -------------- | ----------------- | -------------- | ------------------------------------ | ---------------------- |
| `CODER_AGENT_TOKEN` | Unknown / control-plane session | No (not PADE aud) | Coder control plane only | Workspace/agent ids exist as metadata | Yes (token in env) | **No** |
| Coder user PAT / session | Operator-managed | No | Coder API | Coder user | Yes if stored in workspace | **No** |
| External-auth GitHub token | Provider-dependent | N/A (capability) | GitHub OAuth app | GitHub user/app | Retrieved via Coder; must not be dumped | **No** (wrong layer) |
| Cursor Cloud Agent OIDC | Yes (minted JWT) | Yes | Cursor JWKS | Cursor subject claims | No (socket mint) | **Yes in principle** — **absent here** |
| K8s projected SA OIDC | Yes | Often yes | Cluster OIDC issuer | SA subject | No (projected) | **Yes in principle** — **absent here** |
| Cloud WIF / IRSA / Azure federated | Yes | Exchange-oriented | Cloud IdP | Role/SA subject | Usually no long-lived key in workspace | **Maybe via exchange** — **absent here** |
| SPIFFE JWT-SVID | Yes | Yes | SPIFFE trust domain | SPIFFE ID | No (Workload API) | **Yes in principle** — **absent here** |

## What PADE supports today

Inspected against After-Certainty/pade **v0.2.1** (`d50174a`, same as PADE `main` at experiment time):

```text
identity.TokenSource
        ↓
broker binding provider (Bearer JWT)
        ↓
PADE broker
        ↓
single-issuer OIDC verify (iss/aud/exp + JWKS)
        ↓
subject/capability policy
```

- The `TokenSource` interface is **generic**.
- The only production mint implementation is **Cursor Cloud Agent** socket OIDC.
- `broker.Provider` hard-defaults to Cursor; `broker.identity` accepts only empty/`"cursor"` and does **not** select alternate sources.
- Broker crypto verify is largely generic RS256 + configured issuer/audience/JWKS (default JWKS `https://api.cursor.com/keys` when omitted), but the broker is **single-issuer**.
- Policies with `requireRepoURLs: true` expect Cursor-style complete `repo_urls` claims.

## Architectural preference

Supporting this workspace should **not** begin as “add Coder support to PADE” unless the identity is genuinely Coder-owned OIDC for workloads.

Preferred shape if/when identity appears:

```text
Coder (or other) workspace runtime
      ↓
underlying generic mechanism (e.g. K8s projected OIDC, SPIFFE, cloud WIF)
      ↓
PADE generic TokenSource
      ↓
broker policy pointed at that issuer/JWKS
```

Not preferred without evidence of a Coder-native audience-bound OIDC mint API:

```text
PADE Coder-specific authentication
```

## Smallest likely integration seam (when identity exists)

1. **Neither, first:** configure the workspace/runtime so a real audience-bound OIDC (or exchangeable) identity is available.
2. **TokenSource side:** implement a generic adapter for that mechanism; inject into `broker.Provider.TokenSource` (and eventually relax `broker.identity` validation/wiring).
3. **Broker side:** usually **policy config** (issuer/audience/JWKS; likely `requireRepoURLs: false` unless claims match). **Code** changes only if multi-issuer or non-RS256/non-JWT profiles are required.

On **this** workspace today: **neither** TokenSource nor broker changes help—there is nothing suitable to mint.

## Unknowns

- Whether other Coder deployment modes (Kubernetes templates, cloud identity attachments, future Coder OIDC workload APIs) can expose a TokenSource-fit identity.
- Whether the link-local metadata route ever fronts a real cloud IMDS in other templates (not probed here).
- Whether a deliberate token-exchange service (workspace-native identity → PADE-audience JWT) should be owned by the platform or by PADE.

## Recommended Experiment 005B

Deliberately configure a workspace with an **environment-native, audience-bound (or exchangeable) workload identity**—preferring a generic mechanism such as:

- Coder on Kubernetes with **projected service-account tokens** for a PADE broker audience, or
- SPIFFE/SPIRE, or
- Cloud workload identity + STS exchange,

then re-run discovery and only then prototype a **generic** `TokenSource` (not a Coder-branded PADE auth mode) if the JWT verifies against a known issuer/JWKS.

Do not treat GitHub external-auth success as progress on workload identity.

## Result

```text
Result: no suitable workload identity is currently exposed by this Coder workspace.
Experiment 005B should investigate a deliberate workload-identity configuration.
```

## Safety notes

- `inspect.sh` never prints secret values.
- Generated evidence under `generated/` is gitignored.
- Cursor remote UI must not be confused with Cursor Cloud Agent OIDC.
- Coder agent tokens and external-auth provider tokens must not be reused as PADE broker identity without a deliberate, verifiable trust design.
