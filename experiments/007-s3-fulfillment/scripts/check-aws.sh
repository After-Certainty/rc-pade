#!/usr/bin/env bash
# Experiment 007 AWS preflight. Read-only: never mutates AWS.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

exp007_init_tmp
exp007_load_config
exp007_require_aws_cli

region="$(exp007_resolve_region)"
[[ -n "$region" ]] || die "no AWS region: set AWS_REGION (or AWS_DEFAULT_REGION / aws configure)"
export AWS_REGION="$region" AWS_DEFAULT_REGION="$region"

exp007_caller_identity

show() { printf '%-22s %s\n' "$1" "${2:-<unset>}"; }

printf 'Experiment 007 AWS check (read-only)\n\n'
show "aws_cli" "$(aws --version 2>&1 | head -n 1)"
show "aws_account" "$EXP007_ACCOUNT"
show "caller_arn" "$EXP007_CALLER_ARN"
show "region" "$region"
show "bucket" "$RC_PADE_007_BUCKET"
show "role_name" "$RC_PADE_007_ROLE_NAME"
show "google_sub" "$RC_PADE_007_GOOGLE_SUB"
show "audience" "$RC_PADE_007_AUDIENCE"
if [[ -n "$RC_PADE_007_BUCKET" ]]; then
  show "s3_scope" "s3://$RC_PADE_007_BUCKET/${EXP007_PREFIX}*"
fi

printf '\n## Configuration\n'
config_ok=yes
if ! problems="$(exp007_validate_bootstrap_inputs)"; then
  config_ok=no
  while IFS= read -r line; do
    printf 'warning: %s\n' "$line"
  done <<<"$problems"
fi
show "bootstrap_inputs_ok" "$config_ok"

printf '\n## Existing resources\n'
if exp007_validate_bucket "$RC_PADE_007_BUCKET" >/dev/null; then
  case "$(exp007_bucket_state "$RC_PADE_007_BUCKET" "$EXP007_ACCOUNT")" in
    owned)
      show "bucket_exists" "yes (owned by $EXP007_ACCOUNT)"
      if tags="$(exp007_bucket_tags "$RC_PADE_007_BUCKET" "$EXP007_ACCOUNT" 2>/dev/null)" &&
        exp007_tags_ok <<<"$tags"; then
        show "bucket_tags_ok" "yes"
      else
        show "bucket_tags_ok" "no"
      fi
      ;;
    absent) show "bucket_exists" "no" ;;
    forbidden) show "bucket_exists" "unusable (owned by another account or access denied)" ;;
    *) show "bucket_exists" "unknown (head-bucket failed)" ;;
  esac
else
  show "bucket_exists" "skipped (no valid bucket name)"
fi

role_json="$(exp007_mktemp role)"
case "$(exp007_role_state "$RC_PADE_007_ROLE_NAME" "$role_json")" in
  present)
    show "role_exists" "yes ($(jq -r '.Role.Arn' "$role_json"))"
    if exp007_role_tags "$RC_PADE_007_ROLE_NAME" | exp007_tags_ok; then
      show "role_tags_ok" "yes"
    else
      show "role_tags_ok" "no"
    fi
    if aws iam get-role-policy --role-name "$RC_PADE_007_ROLE_NAME" \
      --policy-name "$EXP007_POLICY_NAME" --output json >/dev/null 2>&1; then
      show "role_policy_exists" "yes ($EXP007_POLICY_NAME)"
    else
      show "role_policy_exists" "no ($EXP007_POLICY_NAME)"
    fi
    ;;
  absent)
    show "role_exists" "no"
    show "role_policy_exists" "no ($EXP007_POLICY_NAME)"
    ;;
  *) show "role_exists" "unknown (get-role failed)" ;;
esac

printf '\nNo AWS resources were modified.\n'
