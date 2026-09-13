#!/usr/bin/env bash
# Safe identity-discovery inspection for Experiment 005.
# Prints only non-secret metadata suitable for public sharing.
# Never prints token values, JWTs, keys, or credential-bearing env values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT="$ROOT/experiments/005-coder-identity-discovery"
GENERATED="$EXPERIMENT/generated"
OUT="$GENERATED/safe-evidence.txt"

mkdir -p "$GENERATED"

# Sensitive names: report presence only, never values.
SENSITIVE_ENV=(
  CODER_AGENT_TOKEN
  CODER_SESSION_TOKEN
  CODER_AGENT_URL
  GIT_ASKPASS
  AWS_SECRET_ACCESS_KEY
  AWS_ACCESS_KEY_ID
  AWS_SESSION_TOKEN
  AWS_WEB_IDENTITY_TOKEN_FILE
  GOOGLE_APPLICATION_CREDENTIALS
  AZURE_CLIENT_SECRET
  AZURE_FEDERATED_TOKEN_FILE
  GITHUB_TOKEN
  GH_TOKEN
  SSH_AUTH_SOCK
  CURSOR_AGENT_SOCKET
)

# Non-secret metadata env: may print values when clearly non-credential.
METADATA_ENV=(
  CODER
  CODER_AGENT_AUTH
  CODER_WORKSPACE_NAME
  CODER_WORKSPACE_OWNER_NAME
  CODER_WORKSPACE_AGENT_NAME
  CODER_WORKSPACE_ID
  CURSOR_AGENT
  KUBERNETES_SERVICE_HOST
  KUBERNETES_SERVICE_PORT
  AWS_ROLE_ARN
  AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
  AWS_CONTAINER_CREDENTIALS_FULL_URI
  GCE_METADATA_HOST
  AZURE_CLIENT_ID
  AZURE_TENANT_ID
  SPIFFE_ENDPOINT_SOCKET
  WORKLOAD_IDENTITY
  KUBECONFIG
)

PATH_CANDIDATES=(
  /var/run/secrets/kubernetes.io/serviceaccount
  /var/run/secrets/eks.amazonaws.com/serviceaccount
  /var/run/secrets/azure/tokens
  /var/run/secrets/tokens
  /var/run/spire/agent/agent.sock
  /tmp/spire-agent/public/api.sock
  /run/spire/sockets/agent.sock
  /var/run/aws-token
  /var/run/aws/token
  /run/cursor/api.sock
  /var/run/secrets/coder.com
  /var/run/coder
  /.dockerenv
  "$HOME/.aws/credentials"
  "$HOME/.aws/config"
  "$HOME/.config/gcloud"
)

presence() {
  local name="$1"
  if printenv "$name" >/dev/null 2>&1; then
    printf '%s=present\n' "$name"
  else
    printf '%s=absent\n' "$name"
  fi
}

section() {
  printf '\n## %s\n' "$1"
}

{
  printf 'Experiment 005 safe identity evidence\n'
  printf 'generated_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'rc_pade_commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'rc_pade_branch=%s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

  section "Host"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'pwd=%s\n' "$(pwd)"
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
  if [[ -r /proc/1/cgroup ]]; then
    printf 'proc1_cgroup_head=%s\n' "$(head -1 /proc/1/cgroup | tr '\n' ' ')"
  fi

  section "Link-local metadata route (no HTTP probe)"
  # Record routing existence only. Do not curl 169.254.169.254.
  if ip route get 169.254.169.254 >/tmp/rc-pade-imds-route.txt 2>/dev/null; then
    printf 'imds_link_local_route=present\n'
    # Sanitize: show only dest/dev/src fields, never credentials.
    awk '{
      for (i=1;i<=NF;i++) {
        if ($i=="via" || $i=="dev" || $i=="src") {
          printf "%s=%s ", $i, $(i+1)
        }
      }
      print ""
    }' /tmp/rc-pade-imds-route.txt | sed 's/[[:space:]]*$//'
  else
    printf 'imds_link_local_route=absent\n'
  fi
  rm -f /tmp/rc-pade-imds-route.txt

  section "Sensitive environment presence"
  for name in "${SENSITIVE_ENV[@]}"; do
    presence "$name"
  done

  section "Metadata environment"
  for name in "${METADATA_ENV[@]}"; do
    if printenv "$name" >/dev/null 2>&1; then
      value="$(printenv "$name")"
      # Only print clearly non-secret short metadata values.
      case "$name" in
        CODER|CODER_AGENT_AUTH|CODER_WORKSPACE_NAME|CODER_WORKSPACE_OWNER_NAME|CODER_WORKSPACE_AGENT_NAME|CURSOR_AGENT)
          printf '%s=%s\n' "$name" "$value"
          ;;
        CODER_WORKSPACE_ID)
          # UUID-like workspace id is operational metadata, not a credential.
          printf '%s=%s\n' "$name" "$value"
          ;;
        *)
          # For other metadata vars: presence + length only if set (avoid leaking paths that may be sensitive).
          if [[ -z "$value" ]]; then
            printf '%s=present_empty\n' "$name"
          else
            printf '%s=present_len=%s\n' "$name" "${#value}"
          fi
          ;;
      esac
    else
      printf '%s=absent\n' "$name"
    fi
  done

  section "Path candidates"
  for path in "${PATH_CANDIDATES[@]}"; do
    if [[ -e "$path" ]]; then
      mode="$(ls -ld "$path" 2>/dev/null | awk '{print $1}')"
      kind=file
      [[ -d "$path" ]] && kind=dir
      [[ -S "$path" ]] && kind=socket
      printf 'PRESENT kind=%s mode=%s path=%s\n' "$kind" "$mode" "$path"
      if [[ -d "$path" ]]; then
        # List names only; never cat token files.
        while IFS= read -r entry; do
          printf '  entry=%s\n' "$(basename "$entry")"
        done < <(find "$path" -maxdepth 1 -mindepth 1 2>/dev/null | sort)
      fi
    else
      printf 'ABSENT  path=%s\n' "$path"
    fi
  done

  section "Tooling presence"
  for cmd in coder kubectl aws gcloud az spire-agent istioctl python3 go git; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf 'tool_%s=present path=%s\n' "$cmd" "$(command -v "$cmd")"
    else
      printf 'tool_%s=absent\n' "$cmd"
    fi
  done

  section "Coder CLI"
  if command -v coder >/dev/null 2>&1; then
    printf 'coder_version=%s\n' "$(coder version 2>/dev/null | head -1 | tr '\n' ' ')"
    printf 'coder_help_auth_related:\n'
    coder --help 2>&1 | grep -iE 'auth|token|agent|whoami|external|login|logout|identity' | sed 's/^/  /' || true
    printf 'coder_external_auth_help:\n'
    coder external-auth --help 2>&1 | sed 's/^/  /' | head -40 || true
    printf 'coder_tokens_help:\n'
    coder tokens --help 2>&1 | sed 's/^/  /' | head -40 || true
    printf 'coder_whoami_help:\n'
    coder whoami --help 2>&1 | sed 's/^/  /' | head -30 || true
    # Safe whoami metadata (username/id/url). Does not print tokens.
    printf 'coder_whoami:\n'
    if coder whoami -o json >/tmp/rc-pade-whoami.json 2>/tmp/rc-pade-whoami.err; then
      python3 - <<'PY'
import json
from pathlib import Path
raw = Path("/tmp/rc-pade-whoami.json").read_text()
data = json.loads(raw)
# Handle common shapes without dumping unexpected fields wholesale.
if isinstance(data, dict):
    for key in ("username", "id", "url", "name", "email"):
        if key in data and data[key] is not None:
            print(f"  {key}={data[key]}")
    orgs = data.get("organization_ids") or data.get("organizations")
    if orgs is not None:
        print(f"  organizations_count={len(orgs) if hasattr(orgs, '__len__') else 'unknown'}")
else:
    print("  whoami_json_shape=unrecognized")
PY
    else
      printf '  whoami_failed=true\n'
      # Print only that help/error occurred; strip anything that looks like a token.
      sed -E 's/[A-Za-z0-9_-]{20,}/[redacted]/g' /tmp/rc-pade-whoami.err | sed 's/^/  /' | head -20 || true
    fi
    rm -f /tmp/rc-pade-whoami.json /tmp/rc-pade-whoami.err
    printf 'note=skipped coder external-auth access-token (would print credentials)\n'
    printf 'note=CODER_AGENT_TOKEN authenticates the workspace agent to the Coder control plane; not treated as PADE TokenSource material\n'
  else
    printf 'coder_cli=absent\n'
  fi

  section "Cursor Cloud Agent identity socket"
  presence CURSOR_AGENT_SOCKET
  if [[ -S /run/cursor/api.sock ]]; then
    printf 'run_cursor_api_sock=present\n'
  else
    printf 'run_cursor_api_sock=absent\n'
  fi
  if printenv CURSOR_AGENT >/dev/null 2>&1; then
    printf 'CURSOR_AGENT=%s\n' "$(printenv CURSOR_AGENT)"
  else
    printf 'CURSOR_AGENT=absent\n'
  fi
  printf 'note=Cursor desktop remote UI is not the same as Cursor Cloud Agent OIDC socket identity\n'

  section "Summary flags"
  printf 'kubernetes_sa_mount=%s\n' "$([[ -e /var/run/secrets/kubernetes.io/serviceaccount ]] && echo present || echo absent)"
  printf 'cursor_cloud_agent_socket=%s\n' "$([[ -S ${CURSOR_AGENT_SOCKET:-/run/cursor/api.sock} ]] && echo present || echo absent)"
  printf 'coder_agent_token=%s\n' "$(printenv CODER_AGENT_TOKEN >/dev/null 2>&1 && echo present || echo absent)"
  printf 'aws_web_identity=%s\n' "$(printenv AWS_WEB_IDENTITY_TOKEN_FILE >/dev/null 2>&1 && echo present || echo absent)"
  printf 'azure_federated_token=%s\n' "$(printenv AZURE_FEDERATED_TOKEN_FILE >/dev/null 2>&1 && echo present || echo absent)"
  printf 'spiffe_socket_env=%s\n' "$(printenv SPIFFE_ENDPOINT_SOCKET >/dev/null 2>&1 && echo present || echo absent)"
} | tee "$OUT"

printf '\nWrote safe evidence to %s\n' "$OUT" >&2
