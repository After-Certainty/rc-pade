#!/usr/bin/env bash
# Experiment 007 Phase 2 preflight from the GCE-backed workspace.
#
# Mints one short-lived GCE metadata ID token for RC_PADE_007_AUDIENCE and
# inspects safe claims in-process. Never calls AWS STS or S3. Never prints the
# token.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gce-aws-lib.sh
. "$SCRIPTS/gce-aws-lib.sh"

gce_aws_refuse_ambient_credentials
require_cmd python3
exec python3 "$SCRIPTS/gce_aws.py" check
