#!/usr/bin/env bash
# Shared helpers for Experiment 007 AWS bootstrap scripts. Source, do not execute.
#
# Never prints credential material. The Google subject and audience are
# identifiers, not bearer credentials.
set -euo pipefail

EXP007_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXP007_ROOT="$(cd "$EXP007_DIR/../.." && pwd)"
EXP007_GENERATED="$EXP007_DIR/generated"

EXP007_PREFIX="experiment-007/"
# shellcheck disable=SC2034 # used by the scripts that source this file
EXP007_POLICY_NAME="experiment-007-s3-put-object"
EXP007_DEFAULT_ROLE_NAME="pade-experiment-007-s3-write"
EXP007_GOOGLE_PROVIDER="accounts.google.com"
EXP007_TAG_PROJECT="rc-pade"
EXP007_TAG_EXPERIMENT="007"
EXP007_TAG_PURPOSE="s3-federation"

export EXP007_ROOT EXP007_GENERATED

log() { printf '%s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# --- temporary files -------------------------------------------------------

EXP007_TMPDIR=""

exp007_init_tmp() {
  EXP007_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/rc-pade-007.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$EXP007_TMPDIR'" EXIT
}

exp007_mktemp() {
  [[ -n "$EXP007_TMPDIR" ]] || die "exp007_init_tmp was not called"
  mktemp "$EXP007_TMPDIR/${1:-tmp}.XXXXXX"
}

# --- configuration ---------------------------------------------------------

exp007_load_config() {
  RC_PADE_007_BUCKET="${RC_PADE_007_BUCKET:-}"
  RC_PADE_007_ROLE_NAME="${RC_PADE_007_ROLE_NAME:-$EXP007_DEFAULT_ROLE_NAME}"
  RC_PADE_007_GOOGLE_SUB="${RC_PADE_007_GOOGLE_SUB:-}"
  RC_PADE_007_AUDIENCE="${RC_PADE_007_AUDIENCE:-}"
}

# Prints the resolved region (possibly empty). Only consults the AWS CLI
# profile when neither AWS_REGION nor AWS_DEFAULT_REGION is set.
exp007_resolve_region() {
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "$region" ]] && command -v aws >/dev/null 2>&1; then
    region="$(aws configure get region 2>/dev/null || true)"
  fi
  printf '%s' "$region"
}

# Validators print a message and return 1 on failure.

exp007_validate_bucket() {
  local b="$1"
  if [[ -z "$b" ]]; then
    echo "RC_PADE_007_BUCKET is not set (explicit, globally unique bucket name required)"
    return 1
  fi
  if ((${#b} < 3 || ${#b} > 63)) ||
    [[ ! "$b" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] ||
    [[ "$b" == *..* ]] ||
    [[ "$b" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    [[ "$b" == xn--* ]]; then
    echo "RC_PADE_007_BUCKET is not a valid S3 bucket name: $b"
    return 1
  fi
}

exp007_validate_role_name() {
  local r="$1"
  if [[ -z "$r" || ! "$r" =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]]; then
    echo "RC_PADE_007_ROLE_NAME is not a valid IAM role name: $r"
    return 1
  fi
}

exp007_validate_google_sub() {
  local s="$1"
  if [[ -z "$s" ]]; then
    echo "RC_PADE_007_GOOGLE_SUB is not set (numeric Google service-account unique ID required)"
    return 1
  fi
  if [[ ! "$s" =~ ^[0-9]{1,64}$ ]]; then
    echo "RC_PADE_007_GOOGLE_SUB must be the numeric service-account unique ID"
    return 1
  fi
}

exp007_validate_audience() {
  local a="$1"
  if [[ -z "$a" ]]; then
    echo "RC_PADE_007_AUDIENCE is not set (exact audience the GCE workload will request)"
    return 1
  fi
  if ((${#a} > 256)) || [[ "$a" =~ [[:space:]] || "$a" == *'*'* || "$a" == *'?'* ]]; then
    echo "RC_PADE_007_AUDIENCE must be a single literal value without whitespace or wildcards"
    return 1
  fi
}

# Validates bucket + role name. Prints all problems; returns 1 if any.
exp007_validate_names() {
  local rc=0
  exp007_validate_bucket "$RC_PADE_007_BUCKET" || rc=1
  exp007_validate_role_name "$RC_PADE_007_ROLE_NAME" || rc=1
  return "$rc"
}

# Validates everything bootstrap needs. Prints all problems; returns 1 if any.
exp007_validate_bootstrap_inputs() {
  local rc=0
  exp007_validate_names || rc=1
  exp007_validate_google_sub "$RC_PADE_007_GOOGLE_SUB" || rc=1
  exp007_validate_audience "$RC_PADE_007_AUDIENCE" || rc=1
  return "$rc"
}

# --- policy rendering (pure, no AWS calls) ---------------------------------

# GCE metadata ID tokens set azp = sub = service-account unique ID, and AWS maps
# accounts.google.com:aud to azp when azp is present. The requested audience
# is therefore matched by accounts.google.com:oaud, which always maps to aud.
exp007_render_trust_policy() {
  local sub="$1" audience="$2"
  jq -n \
    --arg provider "$EXP007_GOOGLE_PROVIDER" \
    --arg sub "$sub" \
    --arg audience "$audience" \
    '{
      Version: "2012-10-17",
      Statement: [{
        Effect: "Allow",
        Principal: {Federated: $provider},
        Action: "sts:AssumeRoleWithWebIdentity",
        Condition: {StringEquals: {
          ($provider + ":aud"): $sub,
          ($provider + ":oaud"): $audience,
          ($provider + ":sub"): $sub
        }}
      }]
    }'
}

exp007_object_arn() {
  printf 'arn:aws:s3:::%s/%s*' "$1" "$EXP007_PREFIX"
}

exp007_render_permissions_policy() {
  local bucket="$1"
  jq -n --arg resource "$(exp007_object_arn "$bucket")" \
    '{
      Version: "2012-10-17",
      Statement: [{
        Effect: "Allow",
        Action: "s3:PutObject",
        Resource: $resource
      }]
    }'
}

exp007_iam_tags_json() {
  jq -cn \
    --arg p "$EXP007_TAG_PROJECT" --arg e "$EXP007_TAG_EXPERIMENT" --arg u "$EXP007_TAG_PURPOSE" \
    '[{Key: "Project", Value: $p}, {Key: "Experiment", Value: $e}, {Key: "Purpose", Value: $u}]'
}

exp007_s3_tagging_json() {
  jq -cn --argjson tags "$(exp007_iam_tags_json)" '{TagSet: $tags}'
}

# Reads a policy document on stdin and prints a canonical form so that
# semantically identical documents compare equal (string vs one-element array,
# key order, statement order).
exp007_canonical_policy() {
  jq -S '
    def arr: if type == "array" then sort else [.] end;
    .Statement |= (
      (if type == "array" then . else [.] end)
      | map(
          (if has("Action") then .Action |= arr else . end)
          | (if has("Resource") then .Resource |= arr else . end)
          | (if (.Principal | type) == "object" then .Principal |= map_values(arr) else . end)
          | (if has("Condition") then .Condition |= map_values(map_values(arr)) else . end)
        )
      | sort_by(tojson)
    )'
}

# Reads a JSON array of {Key, Value} on stdin; succeeds if all expected
# Experiment 007 tags are present with the expected values.
exp007_tags_ok() {
  jq -e \
    --arg p "$EXP007_TAG_PROJECT" --arg e "$EXP007_TAG_EXPERIMENT" --arg u "$EXP007_TAG_PURPOSE" \
    '(map({(.Key): .Value}) | add // {}) as $t
     | $t.Project == $p and $t.Experiment == $e and $t.Purpose == $u' >/dev/null
}

# --- AWS reads -------------------------------------------------------------

exp007_require_aws_cli() {
  require_cmd aws
  require_cmd jq
  aws --version >/dev/null 2>&1 ||
    die "aws CLI is on PATH but does not run ($(command -v aws)); reinstall AWS CLI v2"
}

# Sets EXP007_ACCOUNT and EXP007_CALLER_ARN or dies.
exp007_caller_identity() {
  local ident
  ident="$(aws sts get-caller-identity --output json)" ||
    die "cannot establish AWS caller identity (aws sts get-caller-identity failed)"
  EXP007_ACCOUNT="$(jq -r '.Account // empty' <<<"$ident")"
  EXP007_CALLER_ARN="$(jq -r '.Arn // empty' <<<"$ident")"
  [[ "$EXP007_ACCOUNT" =~ ^[0-9]{12}$ ]] || die "caller identity returned no valid account ID"
  [[ -n "$EXP007_CALLER_ARN" ]] || die "caller identity returned no ARN"
}

# Prints one of: owned | absent | forbidden | error
#   owned     - bucket exists and is owned by the expected account
#   forbidden - bucket exists but is owned by another account or access denied
exp007_bucket_state() {
  local bucket="$1" account="$2" err
  err="$(exp007_mktemp head-bucket)"
  if aws s3api head-bucket --bucket "$bucket" --expected-bucket-owner "$account" >/dev/null 2>"$err"; then
    echo owned
  elif grep -Eq '404|Not Found|NoSuchBucket' "$err"; then
    echo absent
  elif grep -Eq '403|Forbidden|AccessDenied' "$err"; then
    echo forbidden
  else
    echo error
  fi
}

# Prints the bucket region ("us-east-1" when LocationConstraint is null).
exp007_bucket_region() {
  local bucket="$1" account="$2"
  aws s3api get-bucket-location --bucket "$bucket" --expected-bucket-owner "$account" --output json |
    jq -r '.LocationConstraint // "us-east-1" | if . == "" then "us-east-1" else . end'
}

# Prints the bucket TagSet as a JSON array ([] when the bucket has no tags).
exp007_bucket_tags() {
  local bucket="$1" account="$2" out err
  err="$(exp007_mktemp bucket-tags)"
  if out="$(aws s3api get-bucket-tagging --bucket "$bucket" --expected-bucket-owner "$account" --output json 2>"$err")"; then
    jq -c '.TagSet // []' <<<"$out"
  elif grep -q 'NoSuchTagSet' "$err"; then
    echo '[]'
  else
    cat "$err" >&2
    return 1
  fi
}

# Writes the get-role JSON to the given file and prints: present | absent | error
exp007_role_state() {
  local role="$1" out="$2" err
  err="$(exp007_mktemp get-role)"
  if aws iam get-role --role-name "$role" --output json >"$out" 2>"$err"; then
    echo present
  elif grep -q 'NoSuchEntity' "$err"; then
    echo absent
  else
    cat "$err" >&2
    echo error
  fi
}

exp007_role_tags() {
  aws iam list-role-tags --role-name "$1" --output json | jq -c '.Tags // []'
}

exp007_role_inline_policy_names() {
  aws iam list-role-policies --role-name "$1" --output json | jq -c '.PolicyNames // []'
}

exp007_role_attached_policy_arns() {
  aws iam list-attached-role-policies --role-name "$1" --output json |
    jq -c '[.AttachedPolicies[]?.PolicyArn]'
}

# Prompts for an exact confirmation token. Requires an interactive terminal.
exp007_confirm_token() {
  local prompt="$1" expected="$2" answer
  [[ -t 0 ]] || die "confirmation requires an interactive terminal"
  printf '%s' "$prompt" >&2
  IFS= read -r answer || die "no confirmation received"
  [[ "$answer" == "$expected" ]] || die "confirmation did not match; nothing changed"
}
