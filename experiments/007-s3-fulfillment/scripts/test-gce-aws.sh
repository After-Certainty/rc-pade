#!/usr/bin/env bash
# Experiment 007 Phase 2 live experiment from the GCE-backed workspace:
#
#   GCE metadata ID token -> AWS STS AssumeRoleWithWebIdentity
#   -> temporary credentials -> ordinary boto3 PutObject (Experiment 003
#   storage.upload) -> negative boundary checks
#
# Everything credential-bearing happens inside one Python process so nothing
# is persisted between commands. Requires RC_PADE_007_ROLE_ARN.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gce-aws-lib.sh
. "$SCRIPTS/gce-aws-lib.sh"

gce_aws_refuse_ambient_credentials
if [[ -z "${RC_PADE_007_ROLE_ARN:-}" ]]; then
  die "RC_PADE_007_ROLE_ARN must be supplied, e.g. export RC_PADE_007_ROLE_ARN=arn:aws:iam::<account>:role/pade-experiment-007-s3-write"
fi
require_cmd python3
python3 "$SCRIPTS/gce_aws.py" validate-config --require-role-arn >/dev/null

gce_aws_ensure_venv
exec "$GCE_AWS_VENV/bin/python" "$SCRIPTS/gce_aws.py" test
