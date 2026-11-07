#!/usr/bin/env bash
# Recompute Experiment 013 fixture digests and compare to fixtures/SOURCE.txt pins.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FIX="$ROOT/fixtures"
SRC="$FIX/SOURCE.txt"

fail() { printf 'verify-fixtures: FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'verify-fixtures: ok %s\n' "$*"; }

[ -f "$SRC" ] || fail "missing $SRC"

expect() {
  local key="$1" file="$2"
  local want got
  want="$(awk -F': ' -v k="$key" '$1 == k {print $2; exit}' "$SRC")"
  [ -n "$want" ] || fail "missing pin for $key in SOURCE.txt"
  got="$(sha256sum "$file" | awk '{print $1}')"
  [ "$got" = "$want" ] || fail "$file sha256=$got want=$want"
  ok "$key=$got"
}

expect "profile sha256" "$FIX/profile.yaml"
expect "validation-report sha256" "$FIX/validation-report.yaml"
expect "policy sha256" "$FIX/policy.yaml"
expect "allow-capabilities sha256" "$FIX/allow-capabilities.txt"

allow="$(tr -d ' \n\r\t' < "$FIX/allow-capabilities.txt")"
want_allow="$(awk -F': ' '/^allow-capabilities:/{print $2; exit}' "$SRC" | tr -d ' \n\r\t')"
[ "$allow" = "$want_allow" ] || fail "allow-capabilities value mismatch got=$allow want=$want_allow"
ok "allow-capabilities=$allow"

printf 'verify-fixtures: all fixture digests match SOURCE.txt\n'
