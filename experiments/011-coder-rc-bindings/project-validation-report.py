#!/usr/bin/env python3
"""Project a fresh Experiment 009 rcvalidate report into the Experiment 011
adapter KnownFields shape.

This is transport/shape only. It does not change acceptance, validator
module/version, Profile sha256/bytes, or per-condition validity. It does not
loosen the adapter's KnownFields decoding or change Runtime Conditions
semantics.

Usage:
  project-validation-report.py <raw-rcvalidate-report.yaml> <projected-out.yaml>
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

import yaml


REQUIRED_TOP = ("accepted", "validator", "profile", "conditions")
REQUIRED_VALIDATOR = ("module", "version")
REQUIRED_PROFILE = ("sha256", "bytes")
REQUIRED_CONDITION = ("index", "kind", "interfaceType", "valid")


def project_bytes(raw: dict) -> bytes:
    for key in REQUIRED_TOP:
        if key not in raw:
            raise SystemExit(f"missing required top-level field: {key}")
    validator = raw["validator"]
    profile = raw["profile"]
    for key in REQUIRED_VALIDATOR:
        if key not in validator:
            raise SystemExit(f"missing validator.{key}")
    for key in REQUIRED_PROFILE:
        if key not in profile:
            raise SystemExit(f"missing profile.{key}")
    if not isinstance(raw["conditions"], list) or not raw["conditions"]:
        raise SystemExit("conditions must be a non-empty list")

    conditions = []
    for i, condition in enumerate(raw["conditions"]):
        for key in REQUIRED_CONDITION:
            if key not in condition:
                raise SystemExit(f"missing conditions[{i}].{key}")
        conditions.append(
            {
                "index": condition["index"],
                "kind": condition["kind"],
                "interfaceType": condition["interfaceType"],
                "valid": condition["valid"],
            }
        )

    # Fixed layout so projected bytes are deterministic across runs.
    lines = [
        "accepted: true" if raw["accepted"] else "accepted: false",
        "validator:",
        f"  module: {validator['module']}",
        f"  version: {validator['version']}",
        "profile:",
        f"  sha256: {profile['sha256']}",
        f"  bytes: {profile['bytes']}",
        "conditions:",
    ]
    for condition in conditions:
        lines.append(f"- index: {condition['index']}")
        lines.append(f"  kind: {condition['kind']}")
        lines.append(f"  interfaceType: {condition['interfaceType']}")
        lines.append(f"  valid: {'true' if condition['valid'] else 'false'}")
    return ("\n".join(lines) + "\n").encode()


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        raise SystemExit(2)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    raw = yaml.safe_load(src.read_bytes())
    if not isinstance(raw, dict):
        raise SystemExit("report must be a YAML mapping")
    out = project_bytes(raw)
    dst.write_bytes(out)
    print(
        "projected sha256={} bytes={} accepted={} profile.sha256={}".format(
            hashlib.sha256(out).hexdigest(),
            len(out),
            raw["accepted"],
            raw["profile"]["sha256"],
        )
    )


if __name__ == "__main__":
    main()
