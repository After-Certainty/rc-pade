#!/usr/bin/env bash
# Conservative teardown of Experiment 007 AWS resources.
#
# Deletes only resources that exactly match the configured names, live in the
# caller's account, and carry the Experiment 007 tags. Deletes only objects
# under experiment-007/; keeps the bucket if anything else remains.
# Requires typing the role name to confirm.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 0 ]] || die "teardown-aws takes no arguments"

exp007_load_config

if ! problems="$(exp007_validate_names)"; then
  printf '%s\n' "$problems" >&2
  die "refusing to tear down without exact bucket and role names"
fi

exp007_init_tmp
exp007_require_aws_cli

region="$(exp007_resolve_region)"
[[ -n "$region" ]] || die "no AWS region: set AWS_REGION (or AWS_DEFAULT_REGION / aws configure)"
export AWS_REGION="$region" AWS_DEFAULT_REGION="$region"

exp007_caller_identity

bucket="$RC_PADE_007_BUCKET"
role="$RC_PADE_007_ROLE_NAME"
account="$EXP007_ACCOUNT"

# --- inspect role ---------------------------------------------------------

role_file="$(exp007_mktemp role)"
role_state="$(exp007_role_state "$role" "$role_file")"
case "$role_state" in
  present)
    exp007_role_tags "$role" | exp007_tags_ok ||
      die "role $role is not tagged as Experiment 007; refusing to touch it"
    role_arn="$(jq -r '.Role.Arn' "$role_file")"
    [[ "$role_arn" == "arn:aws:iam::$account:role/"* ]] ||
      die "role ARN $role_arn is not in account $account"
    attached="$(exp007_role_attached_policy_arns "$role")"
    [[ "$(jq 'length' <<<"$attached")" == 0 ]] ||
      die "role $role has attached managed policies $attached; refusing to touch it"
    inline_names="$(exp007_role_inline_policy_names "$role")"
    jq -e --arg p "$EXP007_POLICY_NAME" 'all(.[]; . == $p)' <<<"$inline_names" >/dev/null ||
      die "role $role has unexpected inline policies $inline_names; refusing to touch it"
    has_inline="$(jq -r --arg p "$EXP007_POLICY_NAME" 'any(.[]; . == $p)' <<<"$inline_names")"
    ;;
  absent) ;;
  *) die "cannot determine state of role $role" ;;
esac

# --- inspect bucket -------------------------------------------------------

bucket_state="$(exp007_bucket_state "$bucket" "$account")"
keys_file="$(exp007_mktemp keys)"
echo '[]' >"$keys_file"
experiment_count=0
unrelated_count=0
versioning="Unversioned"
case "$bucket_state" in
  owned)
    tags="$(exp007_bucket_tags "$bucket" "$account")" || die "cannot read tags on bucket $bucket"
    exp007_tags_ok <<<"$tags" ||
      die "bucket $bucket is not tagged as Experiment 007; refusing to touch it"
    versioning="$(aws s3api get-bucket-versioning --bucket "$bucket" --expected-bucket-owner "$account" \
      --output json | jq -r '.Status // "Unversioned"')"
    aws s3api list-objects-v2 --bucket "$bucket" --expected-bucket-owner "$account" \
      --output json | jq -c '[.Contents[]?.Key]' >"$keys_file"
    experiment_count="$(jq --arg p "$EXP007_PREFIX" '[.[] | select(startswith($p))] | length' "$keys_file")"
    unrelated_count="$(jq --arg p "$EXP007_PREFIX" '[.[] | select(startswith($p) | not)] | length' "$keys_file")"
    ;;
  absent) ;;
  forbidden) die "bucket $bucket is owned by another account or not accessible; refusing to touch it" ;;
  *) die "cannot determine state of bucket $bucket" ;;
esac

delete_bucket=no
keep_reason=""
if [[ "$bucket_state" == owned ]]; then
  if ((unrelated_count > 0)); then
    keep_reason="$unrelated_count object(s) outside ${EXP007_PREFIX} remain"
  elif [[ "$versioning" != Unversioned ]]; then
    keep_reason="bucket versioning is $versioning (noncurrent versions are not removed by this script)"
  else
    delete_bucket=yes
  fi
fi

# --- plan -----------------------------------------------------------------

printf 'Experiment 007 AWS teardown plan\n\n'
printf 'AWS account:  %s\ncaller:       %s\nregion:       %s\n\n' "$account" "$EXP007_CALLER_ARN" "$region"

if [[ "$bucket_state" == owned ]]; then
  printf 'bucket s3://%s (tagged, owned by %s)\n' "$bucket" "$account"
  printf '  delete %s object(s) under %s\n' "$experiment_count" "$EXP007_PREFIX"
  jq -r --arg p "$EXP007_PREFIX" '[.[] | select(startswith($p))][:20][] | "    - " + .' "$keys_file"
  ((experiment_count > 20)) && printf '    ... and %s more\n' "$((experiment_count - 20))"
  printf '  keep %s unrelated object(s)\n' "$unrelated_count"
  if [[ "$delete_bucket" == yes ]]; then
    printf '  delete bucket once empty\n'
  else
    printf '  KEEP bucket: %s\n' "$keep_reason"
  fi
else
  printf 'bucket s3://%s: absent, nothing to do\n' "$bucket"
fi

if [[ "$role_state" == present ]]; then
  printf 'role %s (tagged)\n' "$role_arn"
  [[ "$has_inline" == true ]] && printf '  delete inline policy %s\n' "$EXP007_POLICY_NAME"
  printf '  delete role\n'
else
  printf 'role %s: absent, nothing to do\n' "$role"
fi
printf '\n'

if [[ "$bucket_state" != owned && "$role_state" != present ]]; then
  log "nothing to tear down"
  exit 0
fi

exp007_confirm_token "Type the role name ($role) to confirm: " "$role"

# --- delete objects under the experiment prefix -----------------------------

if [[ "$bucket_state" == owned ]] && ((experiment_count > 0)); then
  total_batches="$(jq --arg p "$EXP007_PREFIX" '[.[] | select(startswith($p))] | (length + 999) / 1000 | floor' "$keys_file")"
  for ((i = 0; i < total_batches; i++)); do
    batch_file="$(exp007_mktemp delete-batch)"
    jq --arg p "$EXP007_PREFIX" --argjson i "$i" \
      '{Objects: ([.[] | select(startswith($p))][($i * 1000):(($i + 1) * 1000)] | map({Key: .})), Quiet: true}' \
      "$keys_file" >"$batch_file"
    jq -e --arg p "$EXP007_PREFIX" 'all(.Objects[]; .Key | startswith($p))' "$batch_file" >/dev/null ||
      die "internal error: delete batch contains a key outside $EXP007_PREFIX"
    result="$(aws s3api delete-objects --bucket "$bucket" --expected-bucket-owner "$account" \
      --delete "file://$batch_file" --output json)"
    errors="$(jq -n --argjson r "${result:-null}" '[$r.Errors[]?] | length')"
    [[ "$errors" == 0 ]] || die "failed to delete $errors object(s) under $EXP007_PREFIX"
  done
  log "bucket: deleted $experiment_count object(s) under $EXP007_PREFIX"
fi

# --- delete role ----------------------------------------------------------

if [[ "$role_state" == present ]]; then
  if [[ "$has_inline" == true ]]; then
    aws iam delete-role-policy --role-name "$role" --policy-name "$EXP007_POLICY_NAME"
    log "role: deleted inline policy $EXP007_POLICY_NAME"
  fi
  aws iam delete-role --role-name "$role"
  log "role: deleted $role"
fi

# --- delete bucket if empty -----------------------------------------------

if [[ "$delete_bucket" == yes ]]; then
  remaining="$(aws s3api list-objects-v2 --bucket "$bucket" --expected-bucket-owner "$account" \
    --max-items 1 --output json | jq '[.Contents[]?] | length')"
  if [[ "$remaining" == 0 ]]; then
    aws s3api delete-bucket --bucket "$bucket" --expected-bucket-owner "$account"
    log "bucket: deleted $bucket"
  else
    log "bucket: objects appeared during teardown; keeping $bucket"
  fi
elif [[ "$bucket_state" == owned ]]; then
  log "bucket: kept $bucket ($keep_reason)"
fi

log "teardown complete"
