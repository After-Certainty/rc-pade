#!/usr/bin/env bash
# Experiment 011: released PADE v0.4.1 wire-format compatibility (no credentials).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${RC_PADE_011_WORK:-$ROOT/experiments/011-pade-v041-compatibility/generated}"
VERSION="v0.4.1"
SOURCE_COMMIT="05fb0361c8af17c2031b2e3815d252d9cc49bdf7"
POLICY="$ROOT/examples/s3-put-object/policy.yaml"

for required in curl tar go diff python3; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "missing required command: $required" >&2
    exit 1
  }
done

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    ARCH=linux-amd64
    EXPECTED_SHA=1a1832ba627657a00f655312d5fb71894a2c4527edeb43e89b3ded49335fe09b ;;
  Linux-aarch64|Linux-arm64)
    ARCH=linux-arm64
    EXPECTED_SHA=162f7032a4e4a2ba16efa6ed96cdc571ac79d1999d9d2e1f0e50f66b3a351440 ;;
  Darwin-arm64)
    ARCH=darwin-arm64
    EXPECTED_SHA=a32fc54b3cab57ef9e19c4fa1d1579f035b238518290a94e08d6b253b4e195f0 ;;
  *)
    echo "unsupported platform: $(uname -s)-$(uname -m)" >&2
    exit 1 ;;
esac

mkdir -p "$OUT" "$OUT/isolated-home"
ARCHIVE="pade-${VERSION}-${ARCH}.tar.gz"
BASE="https://github.com/After-Certainty/pade/releases/download/${VERSION}"
echo "Fetching checksum-pinned PADE $VERSION ($ARCH)"
curl --fail --location --silent --show-error --retry 3 "${BASE}/${ARCHIVE}" -o "$OUT/$ARCHIVE"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT" && printf '%s  %s\n' "$EXPECTED_SHA" "$ARCHIVE" | sha256sum -c -)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUT" && printf '%s  %s\n' "$EXPECTED_SHA" "$ARCHIVE" | shasum -a 256 -c -)
else
  echo "SHA-256 tool missing" >&2; exit 1
fi

tar -xzf "$OUT/$ARCHIVE" -C "$OUT" pade
PADE="$OUT/pade"
chmod +x "$PADE"
VERSION_OUTPUT="$("$PADE" --version)"
echo "$VERSION_OUTPUT"
if [[ "$VERSION_OUTPUT" != *"$VERSION"* || "$VERSION_OUTPUT" != *"${SOURCE_COMMIT:0:7}"* ]]; then
  echo "PADE version/source mismatch" >&2; exit 1
fi

# Isolate home and bindings: no accidental provider probing or credential use.
run_pade() {
  env -u PADE_BINDINGS HOME="$OUT/isolated-home" \
    PADE_TRUST_WORKSPACE_BINDINGS=0 "$PADE" "$@"
}

verify_fixture() {
  local label="$1" profile="$2" expected="$3"
  local session="$OUT/${label}.development-session.yaml"
  local plan="$OUT/${label}.plan.json"
  echo "Checking $label"
  (cd "$ROOT" && go run ./cmd/rc-pade generate --profile "$profile" \
    --policy "$POLICY" >"$session")
  diff -u "$expected" "$session"
  run_pade validate -f "$session" >"$OUT/${label}.validate.txt"
  run_pade --json plan -f "$session" >"$plan"
  python3 - "$plan" "$label" <<'PY'
import json
import sys
path, label = sys.argv[1:3]
with open(path, encoding="utf-8") as f:
    p = json.load(f)
assert p["apiVersion"] == "pade.local/v1alpha1", (label, "apiVersion")
assert p["kind"] == "DevelopmentSession", (label, "kind")
assert not p.get("bindingsPath"), (label, "unexpected bindings")
caps = p["capabilities"]
assert len(caps) == 1, (label, caps)
c = caps[0]
assert c["name"] == "aws.s3.bucket.write", (label, c)
assert c["access"] == "write", (label, c)
assert c["required"] is True, (label, c)
assert c["bound"] is False, (label, c)
assert c["status"] == "unbound", (label, c)
print(f"PASS {label}: manifest parity, PADE validate and side-effect-free plan")
PY
}

verify_fixture minimal \
  "$ROOT/examples/s3-put-object/runtime-conditions.yaml" \
  "$ROOT/examples/s3-put-object/expected-pade.yaml"
verify_fixture real-rc \
  "$ROOT/experiments/002-real-rc-profile/runtime-conditions.yaml" \
  "$ROOT/experiments/002-real-rc-profile/expected-pade.yaml"

printf 'pade_release=%s\npade_commit=%s\ngo_toolchain=%s\nbroker_execution=not_attempted\n' \
  "$VERSION" "$SOURCE_COMMIT" "$(go version)" >"$OUT/run-provenance.txt"
echo "PASS Experiment 011: PADE v0.4.1 CLI compatibility (2 profiles)"
