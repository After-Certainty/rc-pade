#!/usr/bin/env bash
# Create or reconcile Experiment 007 AWS resources:
#   - S3 bucket (tagged, public access blocked)
#   - IAM role trusting only the configured Google workload via web identity
#   - inline policy granting only s3:PutObject on <bucket>/experiment-007/*
#
# Mutating. Idempotent where practical; fails closed on anything it cannot
# positively identify as this experiment's resource. Creates no access keys.
#
# Usage: bootstrap-aws.sh [--yes]
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assume_yes=no
for arg in "$@"; do
  case "$arg" in
    --yes) assume_yes=yes ;;
    *) die "unknown argument: $arg" ;;
  esac
done

exp007_load_config

# All operator inputs are validated before any AWS call.
if ! problems="$(exp007_validate_bootstrap_inputs)"; then
  printf '%s\n' "$problems" >&2
  die "refusing to bootstrap without a complete, safe trust configuration"
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

trust_file="$(exp007_mktemp trust-policy)"
perms_file="$(exp007_mktemp permissions-policy)"
exp007_render_trust_policy "$RC_PADE_007_GOOGLE_SUB" "$RC_PADE_007_AUDIENCE" >"$trust_file"
exp007_render_permissions_policy "$bucket" >"$perms_file"

cat <<EOF
Experiment 007 AWS bootstrap plan

AWS account:     $account
caller:          $EXP007_CALLER_ARN
region:          $region
bucket:          $bucket
role:            $role
inline policy:   $EXP007_POLICY_NAME
S3 scope:        s3://$bucket/${EXP007_PREFIX}* (s3:PutObject only)
Google subject:  $RC_PADE_007_GOOGLE_SUB
audience:        $RC_PADE_007_AUDIENCE
tags:            Project=$EXP007_TAG_PROJECT Experiment=$EXP007_TAG_EXPERIMENT Purpose=$EXP007_TAG_PURPOSE

Trust policy:
$(jq . "$trust_file")

Permissions policy:
$(jq . "$perms_file")

EOF

if [[ "$assume_yes" != yes ]]; then
  [[ -t 0 ]] || die "not a terminal; re-run interactively or pass --yes"
  printf 'Proceed? [y/N] ' >&2
  IFS= read -r answer || answer=""
  [[ "$answer" == y || "$answer" == Y ]] || die "aborted; nothing changed"
fi

# --- bucket ---------------------------------------------------------------

bucket_state="$(exp007_bucket_state "$bucket" "$account")"
case "$bucket_state" in
  owned)
    tags="$(exp007_bucket_tags "$bucket" "$account")" ||
      die "cannot read tags on existing bucket $bucket"
    exp007_tags_ok <<<"$tags" ||
      die "bucket $bucket exists in account $account but is not tagged as Experiment 007; refusing to adopt it"
    actual_region="$(exp007_bucket_region "$bucket" "$account")" ||
      die "cannot read region of existing bucket $bucket"
    [[ "$actual_region" == "$region" ]] ||
      die "bucket $bucket is in $actual_region, expected $region"
    log "bucket: exists, owned by $account, tagged, region $actual_region"
    ;;
  absent)
    log "bucket: creating $bucket in $region"
    if [[ "$region" == us-east-1 ]]; then
      aws s3api create-bucket --bucket "$bucket" --region "$region" >/dev/null
    else
      aws s3api create-bucket --bucket "$bucket" --region "$region" \
        --create-bucket-configuration "LocationConstraint=$region" >/dev/null
    fi
    aws s3api wait bucket-exists --bucket "$bucket" --expected-bucket-owner "$account"
    aws s3api put-bucket-tagging --bucket "$bucket" --expected-bucket-owner "$account" \
      --tagging "$(exp007_s3_tagging_json)"
    ;;
  forbidden)
    die "bucket $bucket exists but is owned by another account or is not accessible; choose another RC_PADE_007_BUCKET"
    ;;
  *)
    die "cannot determine state of bucket $bucket (head-bucket failed)"
    ;;
esac

aws s3api put-public-access-block --bucket "$bucket" --expected-bucket-owner "$account" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
log "bucket: public access block enforced"

# --- role -----------------------------------------------------------------

role_file="$(exp007_mktemp role)"
role_state="$(exp007_role_state "$role" "$role_file")"
case "$role_state" in
  absent)
    log "role: creating $role"
    aws iam create-role \
      --role-name "$role" \
      --assume-role-policy-document "file://$trust_file" \
      --description "rc-pade Experiment 007: Google web identity -> s3:PutObject on ${bucket}/${EXP007_PREFIX}*" \
      --max-session-duration 3600 \
      --tags "$(exp007_iam_tags_json)" >/dev/null
    aws iam wait role-exists --role-name "$role"
    ;;
  present)
    exp007_role_tags "$role" | exp007_tags_ok ||
      die "role $role exists but is not tagged as Experiment 007; refusing to adopt it"
    actual="$(jq '.Role.AssumeRolePolicyDocument' "$role_file" | exp007_canonical_policy)"
    wanted="$(exp007_canonical_policy <"$trust_file")"
    if [[ "$actual" != "$wanted" ]]; then
      log "role $role has a different trust policy:"
      diff -u <(printf '%s\n' "$wanted") <(printf '%s\n' "$actual") >&2 || true
      die "refusing to rewrite an existing trust relationship; run teardown-aws and bootstrap again if the change is intended"
    fi
    log "role: exists, tagged, trust policy matches"
    ;;
  *)
    die "cannot determine state of role $role (get-role failed)"
    ;;
esac

attached="$(exp007_role_attached_policy_arns "$role")"
[[ "$(jq 'length' <<<"$attached")" == 0 ]] ||
  die "role $role has attached managed policies $attached; refusing to continue"
inline_names="$(exp007_role_inline_policy_names "$role")"
jq -e --arg p "$EXP007_POLICY_NAME" 'all(.[]; . == $p)' <<<"$inline_names" >/dev/null ||
  die "role $role has unexpected inline policies $inline_names; refusing to continue"

aws iam put-role-policy \
  --role-name "$role" \
  --policy-name "$EXP007_POLICY_NAME" \
  --policy-document "file://$perms_file"
log "role: inline policy $EXP007_POLICY_NAME applied"

# --- verify ---------------------------------------------------------------

actual="$(aws iam get-role-policy --role-name "$role" --policy-name "$EXP007_POLICY_NAME" --output json |
  jq '.PolicyDocument' | exp007_canonical_policy)"
[[ "$actual" == "$(exp007_canonical_policy <"$perms_file")" ]] ||
  die "inline policy read back does not match the rendered policy"

actual="$(aws iam get-role --role-name "$role" --output json |
  jq '.Role.AssumeRolePolicyDocument' | exp007_canonical_policy)"
[[ "$actual" == "$(exp007_canonical_policy <"$trust_file")" ]] ||
  die "trust policy read back does not match the rendered policy"

role_arn="$(aws iam get-role --role-name "$role" --query 'Role.Arn' --output text)"

cat <<EOF

Experiment 007 AWS bootstrap complete.

bucket:    s3://$bucket ($region)
role ARN:  $role_arn
scope:     s3:PutObject on arn:aws:s3:::$bucket/${EXP007_PREFIX}*

No access keys were created. No web-identity exchange was performed.
Next: mise run 007:show-aws
EOF
