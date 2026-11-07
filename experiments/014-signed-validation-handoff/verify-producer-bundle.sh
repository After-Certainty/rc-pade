#!/usr/bin/env bash
# Verify the recorded Checkpoint 2 public producer bundle.
# Does not create or require a private signing key.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
BUNDLE="$ROOT/experiments/014-signed-validation-handoff/producer-bundle"
EXPECTED_PROFILE_SHA256="53fe0bca5664c9b889304c881d6643cec163f449a9d02a91fd5a6d635ad62e19"
EXPECTED_PUBKEY_SHA256="2cf313dcc7b0733cdc164e8066dc8aff7134226ba64ed25f63bc48229b7749b6"
RC_DEMOS_REPO="${RC_DEMOS_REPO:-https://github.com/runtimeconditions/rc-demos.git}"
RC_DEMOS_REF="${RC_DEMOS_REF:-853eab3c2c04f9d1059b2dbd64ea91996828a3a9}"
GO_RC_PROFILER_REPO="${GO_RC_PROFILER_REPO:-https://github.com/runtimeconditions/go-rc-profiler.git}"
GO_RC_PROFILER_REF="${GO_RC_PROFILER_REF:-5d2e860e48842b89ec83414123a7e59228f61d36}"
WORK="${RC_PADE_EXPERIMENT_WORK:-$ROOT/.work/experiment-014-verify}"
export PATH="${HOME}/.local/go/bin:${PATH:-}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

if [[ -e "$BUNDLE/signer.key" ]]; then
  echo "refusing: private signing key must not be present under producer-bundle/" >&2
  exit 1
fi

python3 - <<PY
import hashlib, json, pathlib
base = pathlib.Path("$BUNDLE")
prof = (base / "profile.yaml").read_bytes()
pub = (base / "trusted.pub").read_bytes()
ev = json.loads((base / "evidence.json").read_text())
prof_sha = hashlib.sha256(prof).hexdigest()
pub_sha = hashlib.sha256(pub).hexdigest()
assert prof_sha == "$EXPECTED_PROFILE_SHA256", prof_sha
assert pub_sha == "$EXPECTED_PUBKEY_SHA256", pub_sha
assert ev["profile_sha256"] == prof_sha
assert len(pub) == 32
assert (base / "evidence.sig").stat().st_size == 64
for ext in ev["resolved_extensions"]:
    path = base / "extensions" / f"{ext['sha256']}.yaml"
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == ext["sha256"], ext["id"]
print("local_digest_checks_ok")
print(f"profile_sha256={prof_sha} bytes={len(prof)}")
print(f"trusted_pub_sha256={pub_sha}")
PY

mkdir -p "$WORK"
if [[ ! -d "$WORK/rc-demos/.git" ]]; then
  git clone "$RC_DEMOS_REPO" "$WORK/rc-demos"
fi
git -C "$WORK/rc-demos" fetch --depth 1 origin "$RC_DEMOS_REF"
git -C "$WORK/rc-demos" checkout --detach "$RC_DEMOS_REF"

# go.mod replace: ../../go-rc-profiler from validated-profile-handoff → $WORK/go-rc-profiler
if [[ ! -d "$WORK/go-rc-profiler/.git" ]]; then
  git clone "$GO_RC_PROFILER_REPO" "$WORK/go-rc-profiler"
fi
git -C "$WORK/go-rc-profiler" fetch --depth 1 origin "$GO_RC_PROFILER_REF"
git -C "$WORK/go-rc-profiler" checkout --detach "$GO_RC_PROFILER_REF"

VERIFY_GO="$WORK/verify_once.go"
cat > "$VERIFY_GO" <<'EOF'
package main

import (
	"crypto/ed25519"
	"fmt"
	"os"

	"github.com/runtimeconditions/rc-demos/validated-profile-handoff/handoff"
)

func main() {
	pub, err := os.ReadFile(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	profile, err := handoff.Verify(os.Args[1], ed25519.PublicKey(pub))
	if err != nil {
		fmt.Fprintln(os.Stderr, "VERIFY_FAIL", err)
		os.Exit(1)
	}
	fmt.Println("VERIFY_OK", handoff.Digest(profile), len(profile))
}
EOF

(
  cd "$WORK/rc-demos/validated-profile-handoff"
  go run "$VERIFY_GO" "$BUNDLE" "$BUNDLE/trusted.pub"
)

echo "checkpoint-2 producer-bundle verification succeeded"
