#!/usr/bin/env bash
# Show the Experiment 007 AWS configuration. Read-only: never mutates AWS.
# Writes a machine-readable summary to generated/aws-bootstrap.json (gitignored).
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

exp007_init_tmp
exp007_load_config

if ! problems="$(exp007_validate_names)"; then
  printf '%s\n' "$problems" >&2
  die "bucket and role name are required to show Experiment 007 resources"
fi

exp007_require_aws_cli

region="$(exp007_resolve_region)"
[[ -n "$region" ]] || die "no AWS region: set AWS_REGION (or AWS_DEFAULT_REGION / aws configure)"
export AWS_REGION="$region" AWS_DEFAULT_REGION="$region"

exp007_caller_identity

bucket="$RC_PADE_007_BUCKET"
role="$RC_PADE_007_ROLE_NAME"
account="$EXP007_ACCOUNT"

# Runs an AWS read and prints its JSON, or "null" if it fails.
json_or_null() {
  local out
  if out="$("$@" --output json 2>/dev/null)" && [[ -n "$out" ]]; then
    printf '%s' "$out"
  else
    printf 'null'
  fi
}

# --- bucket ---------------------------------------------------------------

bucket_state="$(exp007_bucket_state "$bucket" "$account")"
bucket_json='null'
if [[ "$bucket_state" == owned ]]; then
  bucket_region="$(exp007_bucket_region "$bucket" "$account" 2>/dev/null || echo unknown)"
  bucket_tags="$(exp007_bucket_tags "$bucket" "$account" 2>/dev/null || echo null)"
  pab="$(json_or_null aws s3api get-public-access-block --bucket "$bucket" --expected-bucket-owner "$account")"
  enc="$(json_or_null aws s3api get-bucket-encryption --bucket "$bucket" --expected-bucket-owner "$account")"
  ver="$(json_or_null aws s3api get-bucket-versioning --bucket "$bucket" --expected-bucket-owner "$account")"
  own="$(json_or_null aws s3api get-bucket-ownership-controls --bucket "$bucket" --expected-bucket-owner "$account")"
  bucket_json="$(jq -n \
    --arg name "$bucket" --arg region "$bucket_region" --arg prefix "$EXP007_PREFIX" \
    --argjson tags "$bucket_tags" --argjson pab "$pab" --argjson enc "$enc" \
    --argjson ver "$ver" --argjson own "$own" \
    '{
      name: $name,
      region: $region,
      experimentPrefix: $prefix,
      tags: $tags,
      publicAccessBlock: ($pab.PublicAccessBlockConfiguration // null),
      encryption: ($enc.ServerSideEncryptionConfiguration.Rules // null),
      versioning: ($ver.Status // "Unversioned"),
      ownership: ($own.OwnershipControls.Rules // null)
    }')"
fi

# --- role -----------------------------------------------------------------

role_file="$(exp007_mktemp role)"
role_state="$(exp007_role_state "$role" "$role_file")"
role_json='null'
if [[ "$role_state" == present ]]; then
  role_tags="$(exp007_role_tags "$role" 2>/dev/null || echo null)"
  inline_names="$(exp007_role_inline_policy_names "$role" 2>/dev/null || echo null)"
  attached="$(exp007_role_attached_policy_arns "$role" 2>/dev/null || echo null)"
  inline_doc="$(json_or_null aws iam get-role-policy --role-name "$role" --policy-name "$EXP007_POLICY_NAME")"
  role_json="$(jq -n \
    --slurpfile role "$role_file" --argjson tags "$role_tags" \
    --argjson inlineNames "$inline_names" --argjson attached "$attached" \
    --argjson inline "$inline_doc" --arg policyName "$EXP007_POLICY_NAME" \
    '($role[0].Role) as $r
     | {
        name: $r.RoleName,
        arn: $r.Arn,
        maxSessionDuration: $r.MaxSessionDuration,
        tags: $tags,
        trustPolicy: $r.AssumeRolePolicyDocument,
        trustConditions: [$r.AssumeRolePolicyDocument.Statement[]? | {
          principal: .Principal, action: .Action, condition: .Condition
        }],
        inlinePolicyNames: $inlineNames,
        attachedPolicyArns: $attached,
        permissions: {
          policyName: $policyName,
          document: ($inline.PolicyDocument // null)
        }
      }')"
fi

# --- expected vs actual ----------------------------------------------------

expected_trust='null'
trust_matches='null'
if exp007_validate_google_sub "$RC_PADE_007_GOOGLE_SUB" >/dev/null &&
  exp007_validate_audience "$RC_PADE_007_AUDIENCE" >/dev/null; then
  expected_trust="$(exp007_render_trust_policy "$RC_PADE_007_GOOGLE_SUB" "$RC_PADE_007_AUDIENCE")"
  if [[ "$role_json" != null ]]; then
    actual="$(jq '.trustPolicy' <<<"$role_json" | exp007_canonical_policy)"
    wanted="$(exp007_canonical_policy <<<"$expected_trust")"
    if [[ "$actual" == "$wanted" ]]; then trust_matches=true; else trust_matches=false; fi
  fi
fi
expected_perms="$(exp007_render_permissions_policy "$bucket")"
perms_matches='null'
if [[ "$role_json" != null ]] && jq -e '.permissions.document != null' <<<"$role_json" >/dev/null; then
  actual="$(jq '.permissions.document' <<<"$role_json" | exp007_canonical_policy)"
  wanted="$(exp007_canonical_policy <<<"$expected_perms")"
  if [[ "$actual" == "$wanted" ]]; then perms_matches=true; else perms_matches=false; fi
fi

summary="$(jq -n \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg commit "$(git -C "$EXP007_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
  --arg account "$account" --arg callerArn "$EXP007_CALLER_ARN" --arg region "$region" \
  --arg bucketState "$bucket_state" --arg roleState "$role_state" \
  --arg googleSub "$RC_PADE_007_GOOGLE_SUB" --arg audience "$RC_PADE_007_AUDIENCE" \
  --argjson bucket "$bucket_json" --argjson role "$role_json" \
  --argjson trustMatches "$trust_matches" --argjson permsMatches "$perms_matches" \
  '{
    experiment: "007",
    phase: "aws-bootstrap",
    generatedAtUtc: $generatedAt,
    rcPadeCommit: $commit,
    aws: {account: $account, callerArn: $callerArn, region: $region},
    configured: {
      googleSub: (if $googleSub == "" then null else $googleSub end),
      audience: (if $audience == "" then null else $audience end)
    },
    bucketState: $bucketState,
    bucket: $bucket,
    roleState: $roleState,
    role: $role,
    checks: {
      trustPolicyMatchesConfig: $trustMatches,
      permissionsPolicyMatchesExpected: $permsMatches
    },
    safety: {
      credentialsPrinted: false,
      federationExercised: false,
      s3WritePerformed: false
    }
  }')"

mkdir -p "$EXP007_GENERATED"
out="$EXP007_GENERATED/aws-bootstrap.json"
printf '%s\n' "$summary" >"$out"

jq -r '
  def v: if . == null then "<none>" else (if type == "string" then . else tojson end) end;
  "Experiment 007 AWS configuration (read-only)",
  "",
  "aws_account            \(.aws.account)",
  "region                 \(.aws.region)",
  "",
  "## Bucket (\(.bucketState))",
  (if .bucket then
    "name                   \(.bucket.name)",
    "bucket_region          \(.bucket.region)",
    "experiment_scope       s3://\(.bucket.name)/\(.bucket.experimentPrefix)*",
    "versioning             \(.bucket.versioning)",
    "public_access_block    \(.bucket.publicAccessBlock | v)",
    "encryption             \(.bucket.encryption | v)",
    "ownership              \(.bucket.ownership | v)",
    "tags                   \(.bucket.tags | v)"
   else empty end),
  "",
  "## Role (\(.roleState))",
  (if .role then
    "arn                    \(.role.arn)",
    "max_session_seconds    \(.role.maxSessionDuration)",
    "tags                   \(.role.tags | v)",
    "trust_conditions       \(.role.trustConditions | v)",
    "inline_policies        \(.role.inlinePolicyNames | v)",
    "attached_policies      \(.role.attachedPolicyArns | v)",
    "permissions            \(.role.permissions.document.Statement | v)"
   else empty end),
  "",
  "## Checks",
  "trust_matches_config   \(.checks.trustPolicyMatchesConfig | v)",
  "perms_match_expected   \(.checks.permissionsPolicyMatchesExpected | v)"
' <<<"$summary"

printf '\nWrote %s\nNo AWS resources were modified.\n' "${out#"$EXP007_ROOT"/}"
