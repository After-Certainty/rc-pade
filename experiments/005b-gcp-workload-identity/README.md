# Experiment 005B — GCP workload identity

## 1. Question

Can a Coder workspace running on GCE obtain a short-lived, audience-bound Google-signed identity token and use that as the workload identity primitive for PADE?

```text
Coder workspace on GCE
        ↓
GCE metadata identity service
        ↓
Google-signed audience-bound ID token
        ↓
PADE TokenSource-compatible identity
        ↓
PADE broker verification
```

This experiment is about **identity**, not AWS fulfillment. It does **not** change PADE, provision S3, create AWS credentials, call `gcloud auth login`, create service-account JSON keys, or grant IAM roles.

## How to re-run

```sh
bash experiments/005b-gcp-workload-identity/inspect.sh
```

Optional audience override:

```sh
RC_PADE_TEST_AUDIENCE='https://pade-broker.example' \
  bash experiments/005b-gcp-workload-identity/inspect.sh
```

The script writes shareable evidence to gitignored `generated/safe-evidence.txt`. It never prints raw JWTs, access tokens, service-account keys, or `CODER_AGENT_TOKEN` values. It never queries the GCE metadata `access_token` endpoint.

## 2. Environment

Evidence collected on branch `experiment/gcp-workload-identity` inside Coder workspace `pade-gcp` (owner `ksteffe`, agent `main`).

| Fact | Observation |
|------|-------------|
| Host | Linux 6.1.0-53-cloud-amd64; Debian 12; hostname `coder-ksteffe-pade-gcp-root` |
| DMI | `sys_vendor=Google`, `product_name=Google Compute Engine` |
| Container | `/.dockerenv` **absent** (not the prior Docker/LinuxKit shape from 005A) |
| Coder | `CODER=true`; workspace id `5f866858-46a5-4f74-b0a4-185d42bb50d3` |
| Cursor UI | `CURSOR_AGENT=1` (remote UI flag only; no Cloud Agent OIDC socket used) |
| ADC / gcloud | `GOOGLE_APPLICATION_CREDENTIALS` absent; `~/.config/gcloud` absent |
| Durable keys | None created; no `gcloud auth login` |

## 3. Safe GCE identity evidence

| Fact | Observation |
|------|-------------|
| Metadata root | `metadata.google.internal` HTTP **200** with `Metadata-Flavor: Google` |
| Project ID | `after-certainty` |
| VM name | `coder-ksteffe-pade-gcp-root` |
| Zone | `us-central1-a` |
| Attached service account | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` |
| OAuth scopes | `https://www.googleapis.com/auth/cloud-platform` |
| Clearly GCE | **yes** |

Interpretation: this workspace is a **GCE VM with an attached service account**. Coder owns workspace lifecycle; Google owns the VM identity attachment.

## 4. Token characteristics

Test audience: `https://pade-broker.example` (from [`provenance.yaml`](provenance.yaml)).

| Check | Result |
|-------|--------|
| Structurally a JWT (3 parts) | **true** |
| `alg` | `RS256` |
| `kid` | `f10f87405a979c1df36df26606734f33cd85c271` |
| `iss` | `https://accounts.google.com` |
| `aud` | `https://pade-broker.example` (exact match) |
| `sub` | `107036597357679046851` (stable-looking numeric subject) |
| `email` | `pade-coder-workspace@after-certainty.iam.gserviceaccount.com` |
| Lifetime | **3600s** (short-lived) |
| Durable credentials used to mint | **false** (metadata identity endpoint only) |

Independent local proof (Step 5): fetched Google JWKS (`https://www.googleapis.com/oauth2/v3/certs`) and verified **RS256 signature + issuer + audience + expiration** in-process with stdlib-only PKCS#1 v1.5 SHA-256. Result: `jwks_verify=true`. Raw JWT discarded; never printed or persisted.

## 5. PADE TokenSource compatibility

Inspected After-Certainty/pade **v0.2.1** (`d50174a`, same as PADE `main` at experiment time) via a read-only clone under gitignored `.work/pade`.

```go
// internal/identity/identity.go
type TokenSource interface {
    Token(ctx context.Context, audience string) (Token, error)
}
```

GCE instance identity satisfies this contract **naturally**:

```text
Google TokenSource
    Token(ctx, audience)
        ↓
GET metadata .../identity?audience=<audience>&format=full
  Header: Metadata-Flavor: Google
        ↓
identity.Token{Value: jwt, ExpiresAt: from exp}
```

Only production mint today is Cursor Cloud Agent socket OIDC (`internal/identity/cursor`). `binding/broker.Provider` defaults to that Cursor source and falls back to it when `TokenSource` is nil.

**Naming recommendation:** call the adapter **`google`** (environment-native Google identity). Prefer that over `coder` — Coder did not mint this token. `gce` is an acceptable narrower alias if the implementation is metadata-only and deliberately excludes non-GCE Google runtimes.

## 6. PADE broker compatibility

Broker verify (`internal/broker/verify.go`) is largely **generic**:

- RS256 only
- configured `Issuer`, `Audience`, `JWKSURL`
- required `exp`, non-empty `sub`
- max lifetime 24h (Google’s 1h token fits)
- Cursor claim fields (`repo_urls`, `cloud_agent_id`, …) are parsed when present but **not required** for `Verify` success

Policy (`internal/broker/policy.go`):

- every rule must set `requireRepoURLs` explicitly
- when `requireRepoURLs: false`, authorization is **subject + capability** only
- Google tokens have no `repo_urls` → use `requireRepoURLs: false` for this experiment class (do **not** weaken other checks)

Suggested broker policy shape (not applied in this experiment):

```yaml
oidc:
  issuer: https://accounts.google.com
  audience: https://pade-broker.example
  jwksURL: https://www.googleapis.com/oauth2/v3/certs
policies:
  - subject: "107036597357679046851"
    requireRepoURLs: false
    capabilities:
      - example.capability
```

| Layer | Cursor-specific? | Google fit |
|-------|------------------|------------|
| JWT crypto verify | No (generic RS256 + iss/aud/JWKS) | **Yes** with config |
| Default JWKS if omitted | Defaults to Cursor keys | Must set Google JWKS explicitly |
| `requireRepoURLs: true` | Expects Cursor-style repos | Disable for Google subjects |
| Consumer `broker.identity` allowlist | empty/`cursor` only | Label relaxation is Consumer wiring, not broker crypto |
| Mint path | Cursor socket default | Needs new `TokenSource` |

## 7. Security boundary

```text
Coder
  owns workspace lifecycle

GCP
  owns workload identity (attached SA + metadata identity tokens)

PADE
  consumes workload identity (TokenSource mint + broker verify/policy)
```

This experiment supports that separation: no Coder-specific authentication protocol was required to obtain a PADE-shaped identity primitive.

Safety observed:

- No raw JWT printed or committed
- No access token fetched
- No SA JSON keys / `gcloud auth login`
- No new IAM roles granted
- `CODER_AGENT_TOKEN` presence-only

## 8. Smallest next change

### Outcome A

```text
Existing PADE broker is already compatible.
Only a new generic Google/GCE TokenSource is needed.
```

Evidence:

1. Live Google ID token matches PADE’s verify assumptions (RS256, Google iss, caller aud, short exp, non-empty sub).
2. Independent JWKS signature verification succeeded outside PADE.
3. Broker policy can target Google issuer/JWKS/audience with `requireRepoURLs: false` + subject match.
4. Gap is **mint/wiring**, not broker crypto: implement `internal/identity/google` (name TBD at implementation time), inject into `binding/broker.Provider.TokenSource`, and eventually allow a non-`cursor` `broker.identity` label in Consumer config validation.

Do **not** invent a PADE “Coder auth” mode for this path.

## 9. Recommended Experiment 005C

Dogfood a minimal Google `TokenSource` against a local/dev PADE broker configured for Google OIDC (`requireRepoURLs: false`, subject = this SA’s `sub`), proving end-to-end `Token(ctx, audience)` → Bearer → broker verify/authorize for a **dummy capability** — still **without** AWS fulfillment, S3 provisioning, or broadening workspace credentials.

## 10. Final result

```text
Result: GCE provides a suitable short-lived, audience-bound workload identity.

Coder required no identity integration.

The existing PADE broker can verify it with configuration alone
(issuer/audience/JWKS + requireRepoURLs: false + subject match).

The next smallest PADE change is a generic Google TokenSource
(plus Consumer injection / identity label wiring)—not Coder-specific auth.
```

## Safety notes

- `inspect.sh` never prints secret values or raw JWTs.
- Generated evidence under `generated/` is gitignored.
- GitHub push authority is out of scope; publish via local commit + `git bundle` if needed, same trust boundary as Experiment 004.
