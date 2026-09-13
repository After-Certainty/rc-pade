#!/usr/bin/env bash
# Safe GCE workload-identity inspection for Experiment 005B.
# Prints only non-secret metadata and decoded JWT claim summaries.
# Never prints raw JWTs, access tokens, keys, or credential-bearing env values.
# Never calls the GCE metadata access_token endpoint.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/005b-gcp-workload-identity"
GENERATED="$EXPERIMENT/generated"
OUT="$GENERATED/safe-evidence.txt"
AUDIENCE="${RC_PADE_TEST_AUDIENCE:-https://pade-broker.example}"
METADATA_HOST="${GCE_METADATA_HOST:-metadata.google.internal}"
METADATA_BASE="http://${METADATA_HOST}/computeMetadata/v1"
HEADER="Metadata-Flavor: Google"

mkdir -p "$GENERATED"

section() {
  printf '\n## %s\n' "$1"
}

redact() {
  sed -E 's/[A-Za-z0-9_-]{20,}/[redacted]/g'
}

# Fetch a metadata path. Never used for access_token.
meta_get() {
  local path="$1"
  curl -fsS --connect-timeout 3 -H "$HEADER" "${METADATA_BASE}${path}" 2>/tmp/rc-pade-005b-meta.err || return 1
}

presence() {
  local name="$1"
  if printenv "$name" >/dev/null 2>&1; then
    printf '%s=present\n' "$name"
  else
    printf '%s=absent\n' "$name"
  fi
}

{
  printf 'Experiment 005B safe GCE identity evidence\n'
  printf 'generated_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'rc_pade_commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'rc_pade_branch=%s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  printf 'test_audience=%s\n' "$AUDIENCE"

  section "Host"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'uname=%s\n' "$(uname -srm)"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf 'os_pretty_name=%s\n' "${PRETTY_NAME:-unknown}"
  fi
  if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
    printf 'dmi_sys_vendor=%s\n' "$(tr -d '\0' </sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  else
    printf 'dmi_sys_vendor=absent\n'
  fi
  if [[ -f /sys/class/dmi/id/product_name ]]; then
    printf 'dmi_product_name=%s\n' "$(tr -d '\0' </sys/class/dmi/id/product_name 2>/dev/null || true)"
  else
    printf 'dmi_product_name=absent\n'
  fi
  if [[ -f /.dockerenv ]]; then
    printf 'dockerenv=present\n'
  else
    printf 'dockerenv=absent\n'
  fi

  section "Coder workspace metadata"
  for name in CODER CODER_WORKSPACE_NAME CODER_WORKSPACE_OWNER_NAME CODER_WORKSPACE_AGENT_NAME CODER_WORKSPACE_ID CURSOR_AGENT; do
    if printenv "$name" >/dev/null 2>&1; then
      printf '%s=%s\n' "$name" "$(printenv "$name")"
    else
      printf '%s=absent\n' "$name"
    fi
  done
  presence CODER_AGENT_TOKEN
  presence GOOGLE_APPLICATION_CREDENTIALS
  if [[ -e "$HOME/.config/gcloud" ]]; then
    printf 'gcloud_config_dir=present\n'
  else
    printf 'gcloud_config_dir=absent\n'
  fi
  printf 'note=never calling gcloud auth login; never creating service-account keys\n'

  section "Step1 GCE metadata reachability"
  if curl -fsS --connect-timeout 3 -o /dev/null -w 'metadata_root_http=%{http_code}\n' -H "$HEADER" "${METADATA_BASE}/" 2>/tmp/rc-pade-005b-meta.err; then
    :
  else
    printf 'metadata_root_http=unreachable\n'
    redact </tmp/rc-pade-005b-meta.err | sed 's/^/  /' | head -5 || true
  fi

  if project_id="$(meta_get /project/project-id)"; then
    printf 'project_id=%s\n' "$project_id"
  else
    printf 'project_id=unavailable\n'
  fi
  if instance_name="$(meta_get /instance/name)"; then
    printf 'instance_name=%s\n' "$instance_name"
  else
    printf 'instance_name=unavailable\n'
  fi
  if zone="$(meta_get /instance/zone)"; then
    printf 'zone=%s\n' "$zone"
    printf 'zone_short=%s\n' "$(basename "$zone")"
  else
    printf 'zone=unavailable\n'
  fi
  if sa_list="$(meta_get /instance/service-accounts/)"; then
    printf 'service_accounts=\n'
    printf '%s\n' "$sa_list" | sed 's/^/  /'
  else
    printf 'service_accounts=unavailable\n'
  fi
  if sa_email="$(meta_get /instance/service-accounts/default/email)"; then
    printf 'attached_service_account_email=%s\n' "$sa_email"
  else
    printf 'attached_service_account_email=unavailable\n'
  fi
  if scopes="$(meta_get /instance/service-accounts/default/scopes)"; then
    printf 'oauth_scopes=\n'
    printf '%s\n' "$scopes" | sed 's/^/  /'
  else
    printf 'oauth_scopes=unavailable\n'
  fi
  printf 'note=access_token endpoint deliberately not queried\n'
  printf 'compute_engine_environment=%s\n' "$(
    if [[ -n "${project_id:-}" && -n "${instance_name:-}" && -n "${sa_email:-}" ]]; then
      echo yes
    else
      echo no
    fi
  )"

  section "Step2 audience-bound identity token (claims only)"
  # Fetch JWT into a variable only; never write it to disk or stdout.
  identity_url="${METADATA_BASE}/instance/service-accounts/default/identity?audience=${AUDIENCE}&format=full"
  if RAW_JWT="$(curl -fsS --connect-timeout 5 -H "$HEADER" "$identity_url" 2>/tmp/rc-pade-005b-id.err)"; then
    export RAW_JWT
    export AUDIENCE
    python3 - <<'PY'
import base64, json, os, sys, time

def b64url_decode(segment: str) -> bytes:
    pad = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode(segment + pad)

raw = os.environ.get("RAW_JWT", "")
audience = os.environ["AUDIENCE"]

# Drop env ASAP after copy into local.
os.environ.pop("RAW_JWT", None)

parts = raw.split(".")
print(f"jwt_parts={len(parts)}")
print(f"jwt_structurally_valid={'true' if len(parts) == 3 else 'false'}")
if len(parts) != 3:
    print("decode_ok=false")
    print("error=not_a_jwt")
    sys.exit(0)

try:
    header = json.loads(b64url_decode(parts[0]))
    payload = json.loads(b64url_decode(parts[1]))
except Exception as exc:
    print("decode_ok=false")
    print(f"error={type(exc).__name__}")
    sys.exit(0)

# Clear raw from locals as soon as claims are parsed.
raw = None
parts = None

safe_keys = ("iss", "aud", "sub", "email", "iat", "exp", "azp", "hd", "email_verified")
print("decode_ok=true")
print(f"alg={header.get('alg', '')}")
print(f"kid={header.get('kid', '')}")
print(f"typ={header.get('typ', '')}")
for key in safe_keys:
    if key in payload:
        print(f"{key}={payload[key]}")

now = int(time.time())
iat = payload.get("iat")
exp = payload.get("exp")
if isinstance(iat, int):
    print(f"age_seconds={max(0, now - iat)}")
if isinstance(exp, int):
    ttl = exp - now
    print(f"ttl_seconds={ttl}")
    print(f"short_lived={'true' if 0 < ttl <= 3600 else 'false'}")
    if isinstance(iat, int) and exp > iat:
        print(f"lifetime_seconds={exp - iat}")

aud = payload.get("aud")
print(f"audience_exact_match={'true' if aud == audience else 'false'}")
iss = str(payload.get("iss", ""))
google_iss = iss in (
    "https://accounts.google.com",
    "accounts.google.com",
)
print(f"issuer_is_google={'true' if google_iss else 'false'}")
print(f"subject_nonempty={'true' if bool(payload.get('sub')) else 'false'}")
print("durable_credentials_used=false")
print("note=raw JWT discarded after claim extraction; never printed")
PY
    unset RAW_JWT
  else
    printf 'identity_token_fetch=failed\n'
    redact </tmp/rc-pade-005b-id.err | sed 's/^/  /' | head -10 || true
  fi
  rm -f /tmp/rc-pade-005b-id.err

  section "Step5 optional local JWKS verification"
  # Re-fetch only inside Python so the shell never holds the JWT for this step.
  # Stdlib-only RS256 verify (PKCS#1 v1.5) — no cryptography package required.
  export AUDIENCE METADATA_BASE
  python3 - <<'PY'
import base64, hashlib, json, os, ssl, sys, time, urllib.parse, urllib.request

audience = os.environ["AUDIENCE"]
metadata_base = os.environ["METADATA_BASE"]
jwks_url = "https://www.googleapis.com/oauth2/v3/certs"
identity_url = (
    f"{metadata_base}/instance/service-accounts/default/identity"
    f"?audience={urllib.parse.quote(audience, safe='')}&format=full"
)

# DigestInfo prefix for SHA-256 (RFC 8017 / EMSA-PKCS1-v1_5).
SHA256_DIGESTINFO_PREFIX = bytes.fromhex(
    "3031300d060960864801650304020105000420"
)

def b64url_decode(segment: str) -> bytes:
    pad = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode(segment + pad)

def http_get(url: str, headers=None) -> bytes:
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=10) as resp:
        return resp.read()

def rsa_pkcs1_v15_sha256_verify(n: int, e: int, message: bytes, signature: bytes) -> bool:
    k = (n.bit_length() + 7) // 8
    if len(signature) != k:
        return False
    em = pow(int.from_bytes(signature, "big"), e, n).to_bytes(k, "big")
    digest = hashlib.sha256(message).digest()
    digest_info = SHA256_DIGESTINFO_PREFIX + digest
    # EM = 0x00 || 0x01 || PS || 0x00 || T
    if len(em) < len(digest_info) + 11:
        return False
    if em[0] != 0x00 or em[1] != 0x01:
        return False
    if em[-len(digest_info) - 1] != 0x00:
        return False
    if em[-len(digest_info) :] != digest_info:
        return False
    ps = em[2 : -len(digest_info) - 1]
    return len(ps) >= 8 and all(b == 0xFF for b in ps)

try:
    raw = http_get(identity_url, headers={"Metadata-Flavor": "Google"}).decode("utf-8").strip()
    jwks = json.loads(http_get(jwks_url).decode("utf-8"))
except Exception as exc:
    print("jwks_verify=failed")
    print(f"error={type(exc).__name__}")
    sys.exit(0)

parts = raw.split(".")
if len(parts) != 3:
    print("jwks_verify=failed")
    print("error=not_a_jwt")
    raw = None
    sys.exit(0)

header = json.loads(b64url_decode(parts[0]))
payload = json.loads(b64url_decode(parts[1]))
signed = f"{parts[0]}.{parts[1]}".encode("ascii")
signature = b64url_decode(parts[2])
raw = None
parts = None

kid = header.get("kid")
alg = header.get("alg")
if alg != "RS256":
    print("jwks_verify=failed")
    print(f"error=unsupported_alg_{alg}")
    sys.exit(0)

key = None
for jwk in jwks.get("keys", []):
    if jwk.get("kid") == kid and jwk.get("kty") == "RSA":
        key = jwk
        break
if key is None:
    print("jwks_verify=failed")
    print("error=kid_not_in_jwks")
    sys.exit(0)

n = int.from_bytes(b64url_decode(key["n"]), "big")
e = int.from_bytes(b64url_decode(key["e"]), "big")
if not rsa_pkcs1_v15_sha256_verify(n, e, signed, signature):
    print("jwks_verify=failed")
    print("error=signature_invalid")
    sys.exit(0)

now = int(time.time())
iss = payload.get("iss")
aud = payload.get("aud")
exp = payload.get("exp")
sub = payload.get("sub")
ok_iss = iss in ("https://accounts.google.com", "accounts.google.com")
ok_aud = aud == audience
ok_exp = isinstance(exp, int) and exp > now
ok_sub = bool(sub)

verified = ok_iss and ok_aud and ok_exp and ok_sub
print(f"jwks_verify={'true' if verified else 'false'}")
print("signature_valid=true")
print(f"issuer_ok={'true' if ok_iss else 'false'}")
print(f"audience_ok={'true' if ok_aud else 'false'}")
print(f"expiration_ok={'true' if ok_exp else 'false'}")
print(f"subject_ok={'true' if ok_sub else 'false'}")
print(f"iss={iss}")
print(f"aud={aud}")
print(f"sub={sub}")
if "email" in payload:
    print(f"email={payload['email']}")
if isinstance(exp, int):
    print(f"exp={exp}")
    print(f"ttl_seconds={exp - now}")
print(f"alg={alg}")
print(f"kid={kid}")
print("verify_method=stdlib_rsa_pkcs1_v15_sha256")
print("note=raw JWT discarded after verification; never printed")
PY
  # Keep METADATA_BASE for summary; only drop the exported audience helper.
  unset AUDIENCE || true

  section "Summary flags"
  if curl -fsS --connect-timeout 2 -o /dev/null -H "$HEADER" "${METADATA_BASE}/" >/dev/null 2>&1; then
    printf 'metadata_reachable=yes\n'
  else
    printf 'metadata_reachable=no\n'
  fi
  printf 'no_gcloud_login_used=true\n'
  printf 'no_sa_json_keys_created=true\n'
  printf 'no_access_token_fetched=true\n'
  printf 'no_raw_jwt_printed=true\n'
} | tee "$OUT"

rm -f /tmp/rc-pade-005b-meta.err /tmp/rc-pade-005b-id.err
printf '\nWrote safe evidence to %s\n' "$OUT" >&2
