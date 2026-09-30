#!/usr/bin/env bash
# Offline checks for the Experiment 007 AWS scripts. Requires no AWS
# credentials and never calls AWS: a stub `aws` on PATH fails the test if invoked.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
. "$SCRIPTS/lib.sh"

require_cmd jq

exp007_init_tmp
passed=0

ok() {
  passed=$((passed + 1))
  printf 'ok   %s\n' "$1"
}
fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

# --- syntax / lint --------------------------------------------------------

for f in "$SCRIPTS"/*.sh; do
  bash -n "$f" || fail "bash -n $(basename "$f")"
done
ok "bash -n on all scripts"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$SCRIPTS"/*.sh || fail "shellcheck"
  ok "shellcheck"
else
  printf 'skip shellcheck (not installed)\n'
fi

# --- Phase 1 boundary guard ------------------------------------------------

# The operator bootstrap scripts must stay free of federation and workload
# credential handling; that belongs only to the Phase 2 GCE scripts.
for f in lib.sh check-aws.sh bootstrap-aws.sh show-aws.sh teardown-aws.sh; do
  if grep -Eq 'assume-role-with-web-identity|create-access-key|metadata\.google\.internal|computeMetadata|AWS_SECRET_ACCESS_KEY' "$SCRIPTS/$f"; then
    fail "$f contains federation or credential handling reserved for the Phase 2 scripts"
  fi
done
ok "no web-identity exchange, metadata calls, or access-key handling in Phase 1 scripts"

# --- Phase 2 static safety guards -------------------------------------------

phase2=("$SCRIPTS/gce-aws-lib.sh" "$SCRIPTS/check-gce-aws.sh" "$SCRIPTS/test-gce-aws.sh" "$SCRIPTS/gce_aws.py")
for f in "$SCRIPTS"/*.sh; do
  if grep -Eq '^[[:space:]]*set[[:space:]]+-[a-z]*x|set[[:space:]]+-o[[:space:]]+xtrace' "$f"; then
    fail "$(basename "$f") enables shell tracing"
  fi
done
for f in "${phase2[@]}"; do
  if grep -Eq 'create-access-key|aws[[:space:]]+sts[[:space:]]+assume-role|access_token|\.aws/credentials|aws[[:space:]]+configure[[:space:]]+set|AWS_WEB_IDENTITY_TOKEN_FILE=' "$f"; then
    fail "$(basename "$f") uses a forbidden credential mechanism"
  fi
done
if grep -Eq 'print\([^)]*(token|wrong|creds|Credentials|AccessKeyId|SecretAccessKey|SessionToken)\b' "$SCRIPTS/gce_aws.py"; then
  fail "gce_aws.py prints token or credential material"
fi
if grep -Eq 'logging\.basicConfig|set_stream_logger|boto3\.set_stream_logger' "$SCRIPTS/gce_aws.py"; then
  fail "gce_aws.py enables SDK logging that could expose request bodies"
fi
grep -q 'signature_version=UNSIGNED' "$SCRIPTS/gce_aws.py" || fail "STS exchange must be unsigned (no pre-existing AWS credentials)"
grep -q 'AWS_SHARED_CREDENTIALS_FILE"\] = os.devnull' "$SCRIPTS/gce_aws.py" || fail "shared credential files must be neutralized"
ok "no tracing, CLI token exchange, credential files, or credential printing in Phase 2 scripts"

# --- Phase 2 unit tests (stdlib only) ---------------------------------------

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$SCRIPTS" -p 'test_gce_aws.py' -q 2>&1 | sed 's/^/     /' ||
  fail "gce_aws.py unit tests"
ok "gce_aws.py unit tests"

# --- Phase 2 wrappers refuse before any metadata, STS, or S3 call -----------

ROLE_ARN_FAKE="arn:aws:iam::111122223333:role/pade-experiment-007-s3-write"
# Unroutable metadata host plus an empty venv path: any attempt to go further
# than preflight fails loudly instead of reaching GCE, AWS, or PyPI.
phase2_env=(GCE_METADATA_HOST=127.0.0.1:9 RC_PADE_007_VENV="$EXP007_TMPDIR/no-venv"
  RC_PADE_007_GENERATED_DIR="$EXP007_TMPDIR/generated"
  HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9)

# expect_phase2_refusal <description> <script> <expected stderr substring> [VAR=value ...]
expect_phase2_refusal() {
  local desc="$1" script="$2" want="$3" rc=0 err
  shift 3
  err="$EXP007_TMPDIR/phase2.err"
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN \
    -u AWS_PROFILE -u RC_PADE_007_ROLE_ARN "${phase2_env[@]}" "$@" \
    bash "$SCRIPTS/$script" </dev/null >/dev/null 2>"$err" || rc=$?
  ((rc == 2)) || fail "$desc: expected exit 2, got $rc ($(cat "$err"))"
  grep -qF -- "$want" "$err" || fail "$desc: stderr missing '$want' ($(cat "$err"))"
  [[ ! -e "$EXP007_TMPDIR/no-venv" ]] || fail "$desc: venv was created"
  grep -q 'secret-value' "$err" && fail "$desc: credential value was printed"
  ok "$desc"
}

for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  expect_phase2_refusal "test-gce-aws refuses with $var set" test-gce-aws.sh "$var" \
    "$var=secret-value" RC_PADE_007_ROLE_ARN="$ROLE_ARN_FAKE"
  expect_phase2_refusal "check-gce-aws refuses with $var set" check-gce-aws.sh "$var" "$var=secret-value"
done
expect_phase2_refusal "test-gce-aws refuses without RC_PADE_007_ROLE_ARN" test-gce-aws.sh \
  "RC_PADE_007_ROLE_ARN must be supplied"
expect_phase2_refusal "test-gce-aws refuses a non-007 role ARN" test-gce-aws.sh "RC_PADE_007_ROLE_ARN" \
  RC_PADE_007_ROLE_ARN="arn:aws:iam::111122223333:role/admin"
expect_phase2_refusal "test-gce-aws refuses a malformed role ARN" test-gce-aws.sh "RC_PADE_007_ROLE_ARN" \
  RC_PADE_007_ROLE_ARN="arn:aws:iam::1234:role/pade-experiment-007-s3-write"
expect_phase2_refusal "check-gce-aws refuses an invalid bucket" check-gce-aws.sh "RC_PADE_007_BUCKET" \
  RC_PADE_007_BUCKET="Bad_Bucket"
expect_phase2_refusal "check-gce-aws refuses a wildcard audience" check-gce-aws.sh "RC_PADE_007_AUDIENCE" \
  RC_PADE_007_AUDIENCE="https://*.example"

# With valid config, check must stop at the (unreachable) metadata server and
# must not call AWS: exit 1 with a bounded gce-metadata failure.
rc=0
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
  "${phase2_env[@]}" RC_PADE_007_ROLE_ARN="$ROLE_ARN_FAKE" \
  python3 "$SCRIPTS/gce_aws.py" check </dev/null >/dev/null 2>"$EXP007_TMPDIR/check.err" || rc=$?
((rc == 1)) || fail "check with unreachable metadata: expected exit 1, got $rc"
grep -q 'FAILED gce-metadata' "$EXP007_TMPDIR/check.err" || fail "check should fail at gce-metadata"
ok "check-gce-aws with valid config stops at the metadata server"

# --- policy rendering -------------------------------------------------------

SUB="123456789012345678901"
AUD="https://rc-pade-007.example.invalid"
BUCKET="rc-pade-007-test-bucket"

trust="$(exp007_render_trust_policy "$SUB" "$AUD")"
jq -e --arg sub "$SUB" --arg aud "$AUD" '
  .Version == "2012-10-17"
  and (.Statement | length) == 1
  and .Statement[0].Effect == "Allow"
  and .Statement[0].Principal == {Federated: "accounts.google.com"}
  and .Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
  and (.Statement[0].Condition | keys) == ["StringEquals"]
  and .Statement[0].Condition.StringEquals == {
    "accounts.google.com:aud": $sub,
    "accounts.google.com:oaud": $aud,
    "accounts.google.com:sub": $sub
  }' <<<"$trust" >/dev/null || fail "trust policy shape"
ok "trust policy pins Google provider, aud(azp)=sub, oaud=audience, sub"

if jq -e '[.. | strings | select(test("\\*"))] | length > 0' <<<"$trust" >/dev/null; then
  fail "trust policy contains a wildcard"
fi
ok "trust policy has no wildcards"

perms="$(exp007_render_permissions_policy "$BUCKET")"
jq -e --arg res "arn:aws:s3:::$BUCKET/experiment-007/*" '
  .Version == "2012-10-17"
  and (.Statement | length) == 1
  and .Statement[0].Effect == "Allow"
  and .Statement[0].Action == "s3:PutObject"
  and .Statement[0].Resource == $res
  and (.Statement[0] | keys) == ["Action", "Effect", "Resource"]' <<<"$perms" >/dev/null ||
  fail "permissions policy shape"
ok "permissions policy is exactly s3:PutObject on <bucket>/experiment-007/*"

# Canonical comparison treats string and one-element array as equal but
# still detects a changed audience.
variant="$(jq '.Statement[0].Action = ["sts:AssumeRoleWithWebIdentity"]' <<<"$trust")"
[[ "$(exp007_canonical_policy <<<"$trust")" == "$(exp007_canonical_policy <<<"$variant")" ]] ||
  fail "canonical policy should ignore string vs array"
changed="$(exp007_render_trust_policy "$SUB" "https://other.example.invalid")"
[[ "$(exp007_canonical_policy <<<"$trust")" != "$(exp007_canonical_policy <<<"$changed")" ]] ||
  fail "canonical policy should detect audience change"
ok "canonical policy comparison"

exp007_iam_tags_json | exp007_tags_ok || fail "rendered tags should satisfy tag check"
jq -n '[{Key: "Project", Value: "rc-pade"}, {Key: "Experiment", Value: "007"}]' |
  exp007_tags_ok && fail "missing Purpose tag should fail tag check"
jq -n '[{Key: "Project", Value: "other"}, {Key: "Experiment", Value: "007"}, {Key: "Purpose", Value: "s3-federation"}]' |
  exp007_tags_ok && fail "wrong Project tag should fail tag check"
jq -e '.TagSet | length == 3' <<<"$(exp007_s3_tagging_json)" >/dev/null || fail "s3 tagging json"
ok "tag rendering and tag check"

# --- input validation -------------------------------------------------------

exp007_validate_bucket "$BUCKET" >/dev/null || fail "valid bucket rejected"
for bad in "" "Bad_Bucket" "ab" "a..b" "192.168.0.1" "-bucket"; do
  exp007_validate_bucket "$bad" >/dev/null && fail "invalid bucket accepted: '$bad'"
done
exp007_validate_google_sub "$SUB" >/dev/null || fail "valid sub rejected"
for bad in "" "abc" "123 456" "*"; do
  exp007_validate_google_sub "$bad" >/dev/null && fail "invalid sub accepted: '$bad'"
done
exp007_validate_audience "$AUD" >/dev/null || fail "valid audience rejected"
for bad in "" "has space" "https://*.example" "a?b"; do
  exp007_validate_audience "$bad" >/dev/null && fail "invalid audience accepted: '$bad'"
done
exp007_validate_role_name "$EXP007_DEFAULT_ROLE_NAME" >/dev/null || fail "default role name rejected"
exp007_validate_role_name "bad role" >/dev/null && fail "invalid role name accepted"
ok "input validators"

# --- scripts fail closed before calling AWS --------------------------------

stub_dir="$EXP007_TMPDIR/stub-bin"
marker="$EXP007_TMPDIR/aws-invoked"
mkdir -p "$stub_dir"
cat >"$stub_dir/aws" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$marker"
exit 99
EOF
chmod +x "$stub_dir/aws"

# expect_refusal <description> <script> [VAR=value ...]
# Script arguments come from the script_args array.
script_args=()
expect_refusal() {
  local desc="$1" script="$2" rc=0
  shift 2
  rm -f "$marker"
  env -u RC_PADE_007_BUCKET -u RC_PADE_007_ROLE_NAME -u RC_PADE_007_GOOGLE_SUB \
    -u RC_PADE_007_AUDIENCE -u AWS_PROFILE \
    PATH="$stub_dir:$PATH" AWS_REGION=us-west-2 "$@" \
    bash "$SCRIPTS/$script" ${script_args[@]+"${script_args[@]}"} </dev/null >/dev/null 2>&1 || rc=$?
  ((rc != 0)) || fail "$desc: expected non-zero exit"
  [[ ! -e "$marker" ]] || fail "$desc: aws was invoked ($(cat "$marker"))"
  ok "$desc"
}

complete=(RC_PADE_007_BUCKET="$BUCKET" RC_PADE_007_GOOGLE_SUB="$SUB" RC_PADE_007_AUDIENCE="$AUD")

expect_refusal "bootstrap refuses without RC_PADE_007_GOOGLE_SUB" bootstrap-aws.sh \
  RC_PADE_007_BUCKET="$BUCKET" RC_PADE_007_AUDIENCE="$AUD"
expect_refusal "bootstrap refuses without RC_PADE_007_AUDIENCE" bootstrap-aws.sh \
  RC_PADE_007_BUCKET="$BUCKET" RC_PADE_007_GOOGLE_SUB="$SUB"
expect_refusal "bootstrap refuses without RC_PADE_007_BUCKET" bootstrap-aws.sh \
  RC_PADE_007_GOOGLE_SUB="$SUB" RC_PADE_007_AUDIENCE="$AUD"
expect_refusal "bootstrap refuses non-numeric subject" bootstrap-aws.sh \
  "${complete[@]}" RC_PADE_007_GOOGLE_SUB="not-a-number"
expect_refusal "bootstrap refuses wildcard audience" bootstrap-aws.sh \
  "${complete[@]}" RC_PADE_007_AUDIENCE="https://*.example"
script_args=(--bogus)
expect_refusal "bootstrap rejects unknown arguments" bootstrap-aws.sh "${complete[@]}"
script_args=()
expect_refusal "teardown refuses without RC_PADE_007_BUCKET" teardown-aws.sh
expect_refusal "show refuses without RC_PADE_007_BUCKET" show-aws.sh

# With complete inputs, bootstrap must reach the AWS CLI check (the stub fails
# `aws --version`) rather than doing anything else first.
rm -f "$marker"
rc=0
env PATH="$stub_dir:$PATH" AWS_REGION=us-west-2 "${complete[@]}" \
  bash "$SCRIPTS/bootstrap-aws.sh" --yes </dev/null >/dev/null 2>&1 || rc=$?
((rc != 0)) || fail "bootstrap with stub aws should fail"
[[ "$(cat "$marker" 2>/dev/null)" == "--version" ]] ||
  fail "bootstrap first AWS call should be 'aws --version', got: $(cat "$marker" 2>/dev/null || echo none)"
ok "bootstrap with complete inputs stops at the AWS CLI check"

printf '\n%s checks passed; no AWS calls were made.\n' "$passed"
