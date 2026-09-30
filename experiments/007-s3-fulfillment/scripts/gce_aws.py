#!/usr/bin/env python3
"""Experiment 007 Phase 2: GCE workload identity -> AWS STS -> S3 PutObject.

Subcommands:
  validate-config  offline config + ambient-credential checks (no network)
  check            GCE identity checks only; mints one metadata ID token,
                   never calls AWS
  test             live experiment: STS AssumeRoleWithWebIdentity, ordinary
                   boto3 PutObject via Experiment 003 storage.upload, and
                   negative boundary checks

Raw Google ID tokens and AWS temporary credentials stay in this process's
memory. They are never printed, logged, written to disk, or placed on a
command line. JWT claims are decoded locally for inspection only; they are
not cryptographically verified here. AWS STS accepting the token is the
downstream verification evidence.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
EXPERIMENT_DIR = SCRIPTS_DIR.parent
REPO_ROOT = EXPERIMENT_DIR.parent.parent
GENERATED_DIR = Path(os.environ.get("RC_PADE_007_GENERATED_DIR") or EXPERIMENT_DIR / "generated")
STORAGE_APP_DIR = REPO_ROOT / "experiments" / "003-source-to-session" / "app"

DEFAULT_REGION = "us-east-1"
DEFAULT_BUCKET = "after-certainty-rc-pade-007-1abcdf"
DEFAULT_AUDIENCE = "https://rc-pade-007.after-certainty.aws"
ROLE_NAME = "pade-experiment-007-s3-write"
EXPECTED_SERVICE_ACCOUNT = "pade-coder-workspace@after-certainty.iam.gserviceaccount.com"
GOOGLE_ISSUER = "https://accounts.google.com"
WEB_IDENTITY_PROVIDER = "accounts.google.com"
WRONG_AUDIENCE = "https://rc-pade-007-wrong-audience.after-certainty.aws"
PREFIX = "experiment-007/"
PROOF_KEY = "experiment-007/gce-federation-proof.txt"
OUTSIDE_PREFIX_KEY = "experiment-007-negative/should-not-write.txt"
SESSION_DURATION_SECONDS = 900
DEFAULT_METADATA_HOST = "metadata.google.internal"

CHECK_EVIDENCE = "gce-aws-check.json"
TEST_EVIDENCE = "gce-aws-federation.json"

# Presence of any of these means authority could come from somewhere other
# than GCE identity -> STS. Values are never read beyond presence.
STATIC_CREDENTIAL_VARS = (
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "AWS_SECURITY_TOKEN",
    "AWS_PROFILE",
)

# Other credential-provider inputs neutralized inside this process so boto3
# cannot fall back to them.
NEUTRALIZED_VARS = (
    "AWS_DEFAULT_PROFILE",
    "AWS_ROLE_ARN",
    "AWS_ROLE_SESSION_NAME",
    "AWS_WEB_IDENTITY_TOKEN_FILE",
    "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
    "AWS_CONTAINER_CREDENTIALS_FULL_URI",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE",
)

STS_REJECTION_CODES = frozenset({"AccessDenied", "InvalidIdentityToken"})
S3_DENIAL_CODES = frozenset({"AccessDenied"})

FORBIDDEN_EVIDENCE_KEYS = frozenset(
    {
        "AccessKeyId",
        "SecretAccessKey",
        "SessionToken",
        "WebIdentityToken",
        "Credentials",
        "SubjectFromWebIdentityToken",
        "token",
        "jwt",
        "sub",
    }
)

ROLE_ARN_RE = re.compile(r"^arn:aws:iam::(?P<account>[0-9]{12}):role/(?:[\w+=,.@-]+/)*(?P<name>[\w+=,.@-]+)$")
ASSUMED_ROLE_ARN_RE = re.compile(
    r"^arn:aws:sts::(?P<account>[0-9]{12}):assumed-role/(?P<role>[\w+=,.@-]+)/(?P<session>[\w+=,.@-]+)$"
)
BUCKET_RE = re.compile(r"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$")
REGION_RE = re.compile(r"^[a-z]{2}(-[a-z]+)+-[0-9]$")


class Refusal(Exception):
    """Configuration or environment problem detected before any live call."""


class ExperimentFailure(Exception):
    """A bounded experiment assertion failed."""

    def __init__(self, step: str, reason: str):
        super().__init__(f"{step}: {reason}")
        self.step = step
        self.reason = reason


# --- configuration ----------------------------------------------------------


def resolve_config(env: dict[str, str]) -> dict[str, str]:
    return {
        "region": env.get("AWS_REGION") or DEFAULT_REGION,
        "bucket": env.get("RC_PADE_007_BUCKET") or DEFAULT_BUCKET,
        "audience": env.get("RC_PADE_007_AUDIENCE") or DEFAULT_AUDIENCE,
        "roleArn": env.get("RC_PADE_007_ROLE_ARN", ""),
        "metadataHost": env.get("GCE_METADATA_HOST") or DEFAULT_METADATA_HOST,
    }


def validate_role_arn(arn: str) -> list[str]:
    if not arn:
        return ["RC_PADE_007_ROLE_ARN must be supplied (arn:aws:iam::<account>:role/" + ROLE_NAME + ")"]
    m = ROLE_ARN_RE.match(arn)
    if not m:
        return ["RC_PADE_007_ROLE_ARN is not a syntactically valid IAM role ARN"]
    if m.group("name") != ROLE_NAME:
        return [f"RC_PADE_007_ROLE_ARN must name the Experiment 007 role {ROLE_NAME}"]
    return []


def validate_config(cfg: dict[str, str], require_role_arn: bool) -> tuple[list[str], list[str]]:
    """Returns (problems, role_arn_problems)."""
    problems: list[str] = []
    if not REGION_RE.match(cfg["region"]):
        problems.append("AWS_REGION is not a valid AWS region name")
    b = cfg["bucket"]
    if not BUCKET_RE.match(b) or ".." in b or re.match(r"^\d+\.\d+\.\d+\.\d+$", b):
        problems.append("RC_PADE_007_BUCKET is not a valid S3 bucket name")
    a = cfg["audience"]
    if len(a) > 256 or re.search(r"[\s*?]", a) or not a:
        problems.append("RC_PADE_007_AUDIENCE must be a single literal value without whitespace or wildcards")
    if a == WRONG_AUDIENCE:
        problems.append("RC_PADE_007_AUDIENCE must differ from the negative-test audience")
    if not re.match(r"^[A-Za-z0-9.:-]+$", cfg["metadataHost"]):
        problems.append("GCE_METADATA_HOST is not a plain host[:port]")
    arn_problems = validate_role_arn(cfg["roleArn"])
    if require_role_arn:
        problems.extend(arn_problems)
    return problems, arn_problems


def ambient_credential_vars(env: dict[str, str]) -> list[str]:
    return [name for name in STATIC_CREDENTIAL_VARS if name in env]


# --- redaction / safety -----------------------------------------------------


def redact(text: str) -> str:
    """Redact AWS account IDs and long numeric identifiers (e.g. Google sub)."""
    text = re.sub(r"(?<![0-9])[0-9]{15,}(?![0-9])", "<redacted-number>", text)
    return re.sub(r"(?<![0-9])[0-9]{12}(?![0-9])", "<account>", text)


def assert_evidence_safe(evidence: dict, secrets: list[str]) -> None:
    """Raises ValueError if evidence contains forbidden keys or secret values."""

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in FORBIDDEN_EVIDENCE_KEYS:
                    raise ValueError(f"forbidden evidence key: {k}")
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(evidence)
    blob = json.dumps(evidence)
    for s in secrets:
        if s and s in blob:
            raise ValueError("evidence contains a secret or identifying value")
    if re.search(r"eyJ[A-Za-z0-9_-]{10,}\.", blob):
        raise ValueError("evidence contains a JWT-shaped value")


# --- JWT inspection (local decode only; NOT verification) -------------------


def _b64url(segment: str) -> bytes:
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


def decode_claims(token: str) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ExperimentFailure("google-token", "identity token is not a three-part JWT")
    try:
        claims = json.loads(_b64url(parts[1]))
    except Exception as exc:
        raise ExperimentFailure("google-token", f"payload is not decodable JSON ({type(exc).__name__})") from None
    if not isinstance(claims, dict):
        raise ExperimentFailure("google-token", "payload is not a JSON object")
    return claims


def inspect_claims(claims: dict, audience: str, expected_email: str, now: int | None = None) -> dict:
    """Returns only safe claim facts. Never includes sub or azp values."""
    now = int(dt.datetime.now(dt.timezone.utc).timestamp()) if now is None else now
    sub = claims.get("sub")
    azp = claims.get("azp")
    iat, exp = claims.get("iat"), claims.get("exp")
    gce = (claims.get("google") or {}).get("compute_engine") or {}
    facts = {
        "issuer": claims.get("iss"),
        "issuerOk": claims.get("iss") == GOOGLE_ISSUER,
        "audience": claims.get("aud"),
        "audienceMatched": claims.get("aud") == audience,
        "subPresent": isinstance(sub, str) and bool(sub),
        "azpPresent": isinstance(azp, str) and bool(azp),
        "azpEqualsSub": isinstance(sub, str) and bool(sub) and azp == sub,
        "emailClaim": claims.get("email"),
        "emailMatchesExpected": claims.get("email") == expected_email,
        "emailVerified": claims.get("email_verified"),
        "lifetimeSeconds": exp - iat if isinstance(exp, int) and isinstance(iat, int) else None,
        "expiresInSeconds": exp - now if isinstance(exp, int) else None,
        "computeEngineProjectId": gce.get("project_id"),
        "claimsLocallyDecodedOnly": True,
    }
    return facts


def claim_failures(facts: dict, audience: str) -> list[str]:
    failures = []
    if not facts["issuerOk"]:
        failures.append(f"iss is not {GOOGLE_ISSUER}")
    if not facts["audienceMatched"]:
        failures.append(f"aud does not equal {audience}")
    if not facts["subPresent"]:
        failures.append("sub is missing")
    if not facts["azpPresent"]:
        failures.append("azp is missing")
    if facts["subPresent"] and facts["azpPresent"] and not facts["azpEqualsSub"]:
        failures.append("azp does not equal sub")
    if not facts["emailMatchesExpected"]:
        failures.append(f"email claim is not {EXPECTED_SERVICE_ACCOUNT}")
    exp_in = facts["expiresInSeconds"]
    if exp_in is None or exp_in <= 0:
        failures.append("token is expired or has no exp")
    return failures


# --- AWS error classification ----------------------------------------------


def error_code(exc: BaseException) -> str | None:
    response = getattr(exc, "response", None)
    if isinstance(response, dict):
        return (response.get("Error") or {}).get("Code")
    return None


def classify_rejection(exc: BaseException, expected_codes: frozenset[str]) -> tuple[str, str]:
    """('rejected', code) for an expected authorization denial, else ('inconclusive', detail)."""
    code = error_code(exc)
    if code in expected_codes:
        return "rejected", code
    return "inconclusive", code or type(exc).__name__


# --- GCE metadata -----------------------------------------------------------


class Metadata:
    def __init__(self, host: str):
        self.base = f"http://{host}/computeMetadata/v1"
        # Never route metadata requests through a proxy.
        self._opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def _get(self, path: str, timeout: float = 5.0) -> tuple[str, str | None]:
        req = urllib.request.Request(self.base + path, headers={"Metadata-Flavor": "Google"})
        try:
            with self._opener.open(req, timeout=timeout) as resp:
                return resp.read().decode("utf-8").strip(), resp.headers.get("Metadata-Flavor")
        except urllib.error.HTTPError as exc:
            raise ExperimentFailure("gce-metadata", f"HTTP {exc.code} for {path.split('?')[0]}") from None
        except (urllib.error.URLError, OSError) as exc:
            reason = getattr(exc, "reason", exc)
            raise ExperimentFailure("gce-metadata", f"metadata server unreachable ({type(reason).__name__})") from None

    def get(self, path: str) -> str:
        return self._get(path)[0]

    def environment(self) -> dict:
        value, flavor = self._get("/project/project-id")
        email = self.get("/instance/service-accounts/default/email")
        return {
            "metadataReachable": True,
            "metadataFlavorHeader": flavor,
            "projectId": value,
            "instanceName": self.get("/instance/name"),
            "zone": self.get("/instance/zone").rsplit("/", 1)[-1],
            "serviceAccountEmail": email,
            "serviceAccountMatchesExpected": email == EXPECTED_SERVICE_ACCOUNT,
        }

    def identity_token(self, audience: str) -> str:
        query = urllib.parse.urlencode({"audience": audience, "format": "full"})
        token, _ = self._get(f"/instance/service-accounts/default/identity?{query}")
        return token


# --- shared steps -----------------------------------------------------------


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_facts() -> dict:
    def git(*args: str) -> str:
        try:
            return subprocess.run(
                ["git", "-C", str(REPO_ROOT), *args], capture_output=True, text=True, check=True
            ).stdout.strip()
        except Exception:
            return "unknown"

    return {
        "rcPadeCommit": git("rev-parse", "HEAD"),
        "rcPadeBranch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "worktreeClean": git("status", "--porcelain") == "",
    }


def preflight(env: dict[str, str], require_role_arn: bool) -> tuple[dict, list[str]]:
    cfg = resolve_config(env)
    ambient = ambient_credential_vars(env)
    if ambient:
        raise Refusal(
            "static AWS credential configuration is present; unset it before running the federation proof: "
            + ", ".join(ambient)
        )
    problems, arn_problems = validate_config(cfg, require_role_arn)
    if problems:
        raise Refusal("; ".join(problems))
    return cfg, arn_problems


def gce_identity(cfg: dict, evidence: dict) -> tuple[Metadata, str, dict]:
    md = Metadata(cfg["metadataHost"])
    env_facts = md.environment()
    evidence["gce"] = env_facts
    if env_facts["metadataFlavorHeader"] != "Google":
        raise ExperimentFailure("gce-environment", "metadata response lacks Metadata-Flavor: Google")
    if not env_facts["serviceAccountMatchesExpected"]:
        raise ExperimentFailure("gce-environment", f"attached service account is not {EXPECTED_SERVICE_ACCOUNT}")
    token = md.identity_token(cfg["audience"])
    claims = decode_claims(token)
    facts = inspect_claims(claims, cfg["audience"], EXPECTED_SERVICE_ACCOUNT)
    evidence["googleToken"] = facts
    failures = claim_failures(facts, cfg["audience"])
    if failures:
        raise ExperimentFailure("google-token-claims", "; ".join(failures))
    return md, token, claims


def write_evidence(name: str, evidence: dict, secrets: list[str]) -> Path:
    assert_evidence_safe(evidence, secrets)
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    path = GENERATED_DIR / name
    path.write_text(json.dumps(evidence, indent=2, sort_keys=False) + "\n")
    return path


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def say(label: str, value) -> None:
    print(f"  {label:<34} {value}")


def print_identity_summary(evidence: dict) -> None:
    g, t = evidence.get("gce", {}), evidence.get("googleToken", {})
    if g:
        say("GCE project / zone", f"{g['projectId']} / {g['zone']}")
        say("GCE service account", g["serviceAccountEmail"])
        say("service account matches expected", g["serviceAccountMatchesExpected"])
    if t:
        say("token iss", t["issuer"])
        say("token aud", t["audience"])
        say("aud matches configured", t["audienceMatched"])
        say("sub present / azp present", f"{t['subPresent']} / {t['azpPresent']}")
        say("azp == sub", t["azpEqualsSub"])
        say("email claim matches expected", t["emailMatchesExpected"])
        say("token lifetime (s)", t["lifetimeSeconds"])
        say("claims", "locally decoded only (not verified)")


# --- subcommands ------------------------------------------------------------


def cmd_validate_config(args) -> int:
    preflight(dict(os.environ), require_role_arn=args.require_role_arn)
    print("config ok; no static AWS credential configuration present")
    return 0


def cmd_check(_args) -> int:
    env = dict(os.environ)
    cfg, arn_problems = preflight(env, require_role_arn=False)
    evidence: dict = {
        "schema": "rc-pade/experiment-007/gce-aws-check/v1",
        "generatedAtUtc": now_utc(),
        **git_facts(),
        "config": {
            "region": cfg["region"],
            "bucket": cfg["bucket"],
            "audience": cfg["audience"],
            "roleName": ROLE_NAME,
            "roleArnRedacted": redact(cfg["roleArn"]) if cfg["roleArn"] else None,
            "roleArnValid": not arn_problems,
        },
        "ambientAwsCredentialVars": [],
        "awsCalled": False,
    }
    secrets: list[str] = []
    print("Experiment 007 check-gce-aws (no AWS calls)")
    try:
        _, token, claims = gce_identity(cfg, evidence)
        secrets = [token, str(claims.get("sub", "")), str(claims.get("azp", ""))]
        del token
    except ExperimentFailure as exc:
        evidence["result"] = "failed"
        evidence["failure"] = {"step": exc.step, "reason": redact(exc.reason)}
        print_identity_summary(evidence)
        write_evidence(CHECK_EVIDENCE, evidence, secrets)
        print(f"FAILED {exc.step}: {redact(exc.reason)}", file=sys.stderr)
        return 1
    print_identity_summary(evidence)
    say("region / bucket", f"{cfg['region']} / {cfg['bucket']}")
    say("role ARN", redact(cfg["roleArn"]) if cfg["roleArn"] else "(not set)")
    if arn_problems:
        evidence["result"] = "incomplete"
        path = write_evidence(CHECK_EVIDENCE, evidence, secrets)
        for p in arn_problems:
            print(f"error: {p}", file=sys.stderr)
        print(f"wrote {display_path(path)}")
        return 1
    evidence["result"] = "passed"
    path = write_evidence(CHECK_EVIDENCE, evidence, secrets)
    print(f"check passed; wrote {display_path(path)}")
    return 0


def isolate_aws_environment(region: str) -> None:
    for name in STATIC_CREDENTIAL_VARS + NEUTRALIZED_VARS:
        os.environ.pop(name, None)
    os.environ["AWS_CONFIG_FILE"] = os.devnull
    os.environ["AWS_SHARED_CREDENTIALS_FILE"] = os.devnull
    os.environ["AWS_EC2_METADATA_DISABLED"] = "true"
    os.environ["AWS_REGION"] = region
    os.environ["AWS_DEFAULT_REGION"] = region


def clear_temporary_credentials() -> None:
    for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        os.environ.pop(name, None)


def cmd_test(_args) -> int:
    env = dict(os.environ)
    cfg, _ = preflight(env, require_role_arn=True)
    role_account = ROLE_ARN_RE.match(cfg["roleArn"]).group("account")
    session_name = "rc-pade-007-gce-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    evidence: dict = {
        "schema": "rc-pade/experiment-007/gce-aws-federation/v1",
        "phase": "gce-aws-federation",
        "generatedAtUtc": now_utc(),
        **git_facts(),
        "config": {
            "region": cfg["region"],
            "bucket": cfg["bucket"],
            "audience": cfg["audience"],
            "roleName": ROLE_NAME,
            "roleArnRedacted": redact(cfg["roleArn"]),
            "allowedResource": f"arn:aws:s3:::{cfg['bucket']}/{PREFIX}*",
        },
        "ambientAwsCredentialVars": [],
    }
    secrets: list[str] = [role_account]

    print("Experiment 007 test-gce-aws (live: GCE metadata, AWS STS, S3)")
    try:
        md, token, claims = gce_identity(cfg, evidence)
        secrets += [token, str(claims.get("sub", "")), str(claims.get("azp", ""))]
        print_identity_summary(evidence)

        isolate_aws_environment(cfg["region"])
        import boto3
        from botocore import UNSIGNED
        from botocore.config import Config
        from botocore.exceptions import BotoCoreError, ClientError

        evidence["awsSdk"] = {"boto3": boto3.__version__, "botocore": __import__("botocore").__version__}
        if boto3.Session().get_credentials() is not None:
            raise ExperimentFailure("ambient-credentials", "boto3 resolved credentials before STS exchange")
        evidence["defaultChainCredentialsBeforeSts"] = None

        unsigned = Config(signature_version=UNSIGNED, retries={"max_attempts": 2, "mode": "standard"})
        sts = boto3.Session().client("sts", region_name=cfg["region"], config=unsigned)

        # Correct-audience exchange.
        try:
            resp = sts.assume_role_with_web_identity(
                RoleArn=cfg["roleArn"],
                RoleSessionName=session_name,
                WebIdentityToken=token,
                DurationSeconds=SESSION_DURATION_SECONDS,
            )
        except (ClientError, BotoCoreError) as exc:
            raise ExperimentFailure(
                "sts-assume-role", f"correct-audience token was not accepted ({error_code(exc) or type(exc).__name__})"
            ) from None
        finally:
            del token
        creds = resp["Credentials"]
        secrets += [creds["AccessKeyId"], creds["SecretAccessKey"], creds["SessionToken"]]
        assumed_arn = resp["AssumedRoleUser"]["Arn"]
        m = ASSUMED_ROLE_ARN_RE.match(assumed_arn)
        sts_facts = {
            "assumeRoleWithWebIdentity": "accepted",
            "assumedRoleArnRedacted": redact(assumed_arn),
            "sessionName": session_name,
            "durationSeconds": SESSION_DURATION_SECONDS,
            "expiration": creds["Expiration"].astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "provider": resp.get("Provider"),
            "tokenAudience": cfg["audience"],
            "stsSubjectMatchesTokenSub": resp.get("SubjectFromWebIdentityToken") == claims.get("sub"),
        }
        evidence["sts"] = sts_facts
        if not (m and m.group("account") == role_account and m.group("role") == ROLE_NAME
                and m.group("session") == session_name):
            raise ExperimentFailure("sts-assume-role", "assumed-role ARN does not match the Experiment 007 role")

        # Temporary credentials enter the ordinary boto3 chain through this
        # process's environment only. No subprocess is started after this.
        os.environ["AWS_ACCESS_KEY_ID"] = creds["AccessKeyId"]
        os.environ["AWS_SECRET_ACCESS_KEY"] = creds["SecretAccessKey"]
        os.environ["AWS_SESSION_TOKEN"] = creds["SessionToken"]
        del creds, resp

        chain = boto3.Session()
        sts_facts["workloadCredentialSource"] = chain.get_credentials().method
        ident = chain.client("sts").get_caller_identity()
        sts_facts["callerIdentityArnRedacted"] = redact(ident["Arn"])
        sts_facts["callerIdentityMatchesAssumedRole"] = ident["Arn"] == assumed_arn
        if not sts_facts["callerIdentityMatchesAssumedRole"]:
            raise ExperimentFailure("caller-identity", "temporary credentials do not represent the assumed role")

        say("STS AssumeRoleWithWebIdentity", "accepted")
        say("assumed role", redact(assumed_arn))
        say("credential expiration", sts_facts["expiration"])
        say("workload credential source", sts_facts["workloadCredentialSource"])

        # Positive proof: unmodified Experiment 003 application code.
        sys.path.insert(0, str(STORAGE_APP_DIR))
        import storage  # noqa: E402

        with tempfile.TemporaryDirectory(prefix="rc-pade-007-") as tmp:
            body = Path(tmp) / "proof.txt"
            body.write_text(
                "rc-pade Experiment 007 Phase 2 GCE federation proof\n"
                f"rc_pade_commit={evidence['rcPadeCommit']}\n"
                f"session_name={session_name}\n"
                f"written_at_utc={now_utc()}\n"
            )
            try:
                etag = storage.upload(cfg["bucket"], PROOF_KEY, body)
            except (ClientError, BotoCoreError) as exc:
                evidence["s3PutObject"] = {"success": False, "key": PROOF_KEY, "errorCode": error_code(exc)}
                raise ExperimentFailure("s3-put-object", f"PutObject under {PREFIX} failed ({error_code(exc)})") from None
        evidence["s3PutObject"] = {
            "success": True,
            "key": PROOF_KEY,
            "etag": etag,
            "via": "experiments/003-source-to-session/app/storage.py upload()",
        }
        say("PutObject " + PROOF_KEY, f"succeeded (ETag {etag})")

        negatives: dict = {}
        evidence["negativeTests"] = negatives

        # A. Wrong audience must be rejected by STS.
        wrong = md.identity_token(WRONG_AUDIENCE)
        secrets.append(wrong)
        wrong_facts = inspect_claims(decode_claims(wrong), WRONG_AUDIENCE, EXPECTED_SERVICE_ACCOUNT)
        try:
            sts.assume_role_with_web_identity(
                RoleArn=cfg["roleArn"],
                RoleSessionName=session_name + "-neg",
                WebIdentityToken=wrong,
                DurationSeconds=SESSION_DURATION_SECONDS,
            )
            negatives["wrongAudience"] = {"audience": WRONG_AUDIENCE, "result": "ACCEPTED"}
            raise ExperimentFailure("negative-wrong-audience", "STS accepted a wrong-audience token; trust policy is too broad")
        except (ClientError, BotoCoreError) as exc:
            outcome, code = classify_rejection(exc, STS_REJECTION_CODES)
            negatives["wrongAudience"] = {
                "audience": WRONG_AUDIENCE,
                "tokenAudMatchedWrongAudience": wrong_facts["audienceMatched"],
                "result": outcome,
                "errorCode": code,
            }
            if outcome != "rejected":
                raise ExperimentFailure("negative-wrong-audience", f"inconclusive STS error ({code})") from None
        finally:
            del wrong
        say("wrong-audience AssumeRole", f"rejected ({negatives['wrongAudience']['errorCode']})")

        s3 = boto3.client("s3")

        # B. PutObject outside experiment-007/ must be denied.
        try:
            s3.put_object(Bucket=cfg["bucket"], Key=OUTSIDE_PREFIX_KEY, Body=b"should not be written\n")
            negatives["outsidePrefixPutObject"] = {"key": OUTSIDE_PREFIX_KEY, "result": "ALLOWED"}
            raise ExperimentFailure("negative-outside-prefix", "PutObject outside experiment-007/ succeeded")
        except (ClientError, BotoCoreError) as exc:
            outcome, code = classify_rejection(exc, S3_DENIAL_CODES)
            negatives["outsidePrefixPutObject"] = {"key": OUTSIDE_PREFIX_KEY, "result": outcome, "errorCode": code}
            if outcome != "rejected":
                raise ExperimentFailure("negative-outside-prefix", f"inconclusive S3 error ({code})") from None
        say("PutObject " + OUTSIDE_PREFIX_KEY, f"denied ({negatives['outsidePrefixPutObject']['errorCode']})")

        # C. Non-PutObject authority (ListObjectsV2) must be denied.
        try:
            s3.list_objects_v2(Bucket=cfg["bucket"], Prefix=PREFIX, MaxKeys=1)
            negatives["listObjectsV2"] = {"prefix": PREFIX, "result": "ALLOWED"}
            raise ExperimentFailure("negative-list-objects", "ListObjectsV2 succeeded; role has more than PutObject")
        except (ClientError, BotoCoreError) as exc:
            outcome, code = classify_rejection(exc, S3_DENIAL_CODES)
            negatives["listObjectsV2"] = {"prefix": PREFIX, "result": outcome, "errorCode": code}
            if outcome != "rejected":
                raise ExperimentFailure("negative-list-objects", f"inconclusive S3 error ({code})") from None
        say("ListObjectsV2", f"denied ({negatives['listObjectsV2']['errorCode']})")

    except ExperimentFailure as exc:
        clear_temporary_credentials()
        evidence["result"] = "failed"
        evidence["failure"] = {"step": exc.step, "reason": redact(exc.reason)}
        evidence["safety"] = safety_facts()
        path = write_evidence(TEST_EVIDENCE, evidence, secrets)
        print(f"FAILED {exc.step}: {redact(exc.reason)}", file=sys.stderr)
        print(f"wrote {display_path(path)}", file=sys.stderr)
        return 1

    clear_temporary_credentials()
    evidence["result"] = "passed"
    evidence["safety"] = safety_facts()
    path = write_evidence(TEST_EVIDENCE, evidence, secrets)
    print(f"Experiment 007 Phase 2 passed; wrote {display_path(path)}")
    return 0


def safety_facts() -> dict:
    return {
        "durableAwsCredentialsUsed": False,
        "awsProfileUsed": False,
        "sharedCredentialFilesUsed": False,
        "rawGoogleTokenRecorded": False,
        "temporaryCredentialsRecorded": False,
        "temporaryCredentialsPersisted": False,
        "claimsCryptographicallyVerifiedLocally": False,
        "verificationEvidence": "AWS STS acceptance of the correct-audience token",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    vc = sub.add_parser("validate-config")
    vc.add_argument("--require-role-arn", action="store_true")
    vc.set_defaults(func=cmd_validate_config)
    sub.add_parser("check").set_defaults(func=cmd_check)
    sub.add_parser("test").set_defaults(func=cmd_test)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Refusal as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
