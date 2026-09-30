"""Offline unit tests for gce_aws.py. No network, GCE, or AWS access."""

import base64
import json
import unittest

import gce_aws as g

ACCOUNT = "111122223333"
ROLE_ARN = f"arn:aws:iam::{ACCOUNT}:role/{g.ROLE_NAME}"
SUB = "104857600000000000001"


def b64(obj) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def fake_jwt(**claims) -> str:
    return f"{b64({'alg': 'RS256', 'typ': 'JWT'})}.{b64(claims)}.c2lnbmF0dXJl"


def good_claims(**overrides):
    claims = {
        "iss": g.GOOGLE_ISSUER,
        "aud": g.DEFAULT_AUDIENCE,
        "sub": SUB,
        "azp": SUB,
        "email": g.EXPECTED_SERVICE_ACCOUNT,
        "email_verified": True,
        "iat": 1000,
        "exp": 4600,
    }
    claims.update(overrides)
    return claims


class ConfigTests(unittest.TestCase):
    def test_defaults(self):
        cfg = g.resolve_config({})
        self.assertEqual(cfg["region"], "us-east-1")
        self.assertEqual(cfg["bucket"], "after-certainty-rc-pade-007-1abcdf")
        self.assertEqual(cfg["audience"], "https://rc-pade-007.after-certainty.aws")
        self.assertEqual(cfg["roleArn"], "")

    def test_overrides(self):
        cfg = g.resolve_config({"AWS_REGION": "us-west-2", "RC_PADE_007_BUCKET": "b-c-d", "RC_PADE_007_ROLE_ARN": ROLE_ARN})
        self.assertEqual((cfg["region"], cfg["bucket"], cfg["roleArn"]), ("us-west-2", "b-c-d", ROLE_ARN))

    def test_role_arn_validation(self):
        self.assertEqual(g.validate_role_arn(ROLE_ARN), [])
        self.assertEqual(g.validate_role_arn(f"arn:aws:iam::{ACCOUNT}:role/path/{g.ROLE_NAME}"), [])
        self.assertIn("RC_PADE_007_ROLE_ARN must be supplied", g.validate_role_arn("")[0])
        for bad in (
            f"arn:aws:iam::{ACCOUNT}:role/other-role",
            f"arn:aws:iam::12345:role/{g.ROLE_NAME}",
            f"arn:aws:iam::{ACCOUNT}:user/{g.ROLE_NAME}",
            f"arn:aws:iam::{ACCOUNT}:role/{g.ROLE_NAME}*",
            f"arn:aws:sts::{ACCOUNT}:assumed-role/{g.ROLE_NAME}/x",
        ):
            self.assertTrue(g.validate_role_arn(bad), bad)

    def test_config_validation(self):
        problems, arn = g.validate_config(g.resolve_config({}), require_role_arn=False)
        self.assertEqual(problems, [])
        self.assertTrue(arn)
        problems, _ = g.validate_config(g.resolve_config({}), require_role_arn=True)
        self.assertTrue(any("RC_PADE_007_ROLE_ARN" in p for p in problems))
        for env in (
            {"AWS_REGION": "nowhere"},
            {"RC_PADE_007_BUCKET": "Bad_Bucket"},
            {"RC_PADE_007_AUDIENCE": "https://*.example"},
            {"RC_PADE_007_AUDIENCE": g.WRONG_AUDIENCE},
            {"GCE_METADATA_HOST": "evil/host?x"},
        ):
            problems, _ = g.validate_config(g.resolve_config(env), require_role_arn=False)
            self.assertTrue(problems, env)

    def test_ambient_credentials(self):
        self.assertEqual(g.ambient_credential_vars({"HOME": "/x"}), [])
        self.assertEqual(
            g.ambient_credential_vars({"AWS_ACCESS_KEY_ID": "x", "AWS_PROFILE": "p"}),
            ["AWS_ACCESS_KEY_ID", "AWS_PROFILE"],
        )
        with self.assertRaises(g.Refusal):
            g.preflight({"AWS_SECRET_ACCESS_KEY": "x", "RC_PADE_007_ROLE_ARN": ROLE_ARN}, True)
        with self.assertRaises(g.Refusal):
            g.preflight({}, True)
        cfg, _ = g.preflight({"RC_PADE_007_ROLE_ARN": ROLE_ARN}, True)
        self.assertEqual(cfg["roleArn"], ROLE_ARN)


class RedactionTests(unittest.TestCase):
    def test_redact_account_and_subject(self):
        arn = f"arn:aws:sts::{ACCOUNT}:assumed-role/{g.ROLE_NAME}/rc-pade-007-gce-20260930T030000Z"
        redacted = g.redact(arn)
        self.assertEqual(redacted, f"arn:aws:sts::<account>:assumed-role/{g.ROLE_NAME}/rc-pade-007-gce-20260930T030000Z")
        self.assertNotIn(ACCOUNT, redacted)
        self.assertNotIn(SUB, g.redact(f"subject {SUB}"))

    def test_evidence_safety(self):
        token = fake_jwt(**good_claims())
        g.assert_evidence_safe({"sts": {"assumedRoleArnRedacted": "arn:aws:sts::<account>:x"}}, [token, SUB, ACCOUNT])
        for bad in (
            {"x": {"SessionToken": "abc"}},
            {"x": {"sub": "abc"}},
            {"arn": f"arn:aws:iam::{ACCOUNT}:role/x"},
            {"t": token},
            {"s": SUB},
            {"t": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.sig"},
        ):
            with self.assertRaises(ValueError, msg=bad):
                g.assert_evidence_safe(bad, [token, SUB, ACCOUNT])


class ClaimTests(unittest.TestCase):
    def test_good_claims(self):
        facts = g.inspect_claims(g.decode_claims(fake_jwt(**good_claims())), g.DEFAULT_AUDIENCE, g.EXPECTED_SERVICE_ACCOUNT, now=2000)
        self.assertEqual(g.claim_failures(facts, g.DEFAULT_AUDIENCE), [])
        self.assertTrue(facts["azpEqualsSub"])
        self.assertTrue(facts["claimsLocallyDecodedOnly"])
        self.assertEqual(facts["lifetimeSeconds"], 3600)
        self.assertNotIn(SUB, json.dumps(facts))

    def check_fails(self, expected, **overrides):
        claims = good_claims(**overrides)
        for k, v in list(claims.items()):
            if v is None:
                del claims[k]
        facts = g.inspect_claims(claims, g.DEFAULT_AUDIENCE, g.EXPECTED_SERVICE_ACCOUNT, now=2000)
        failures = g.claim_failures(facts, g.DEFAULT_AUDIENCE)
        self.assertTrue(any(expected in f for f in failures), failures)

    def test_bad_claims(self):
        self.check_fails("iss", iss="https://evil.example")
        self.check_fails("aud", aud="https://other.example")
        self.check_fails("sub is missing", sub=None)
        self.check_fails("azp is missing", azp=None)
        self.check_fails("azp does not equal sub", azp="999")
        self.check_fails("email", email="someone@else.iam.gserviceaccount.com")
        self.check_fails("expired", exp=1500)

    def test_malformed_token(self):
        for bad in ("", "a.b", "a.!!!.c", f"x.{base64.urlsafe_b64encode(b'[1]').decode()}.y"):
            with self.assertRaises(g.ExperimentFailure):
                g.decode_claims(bad)


class ClassificationTests(unittest.TestCase):
    class FakeClientError(Exception):
        def __init__(self, code):
            super().__init__(code)
            self.response = {"Error": {"Code": code, "Message": "m"}}

    def test_rejection(self):
        self.assertEqual(g.classify_rejection(self.FakeClientError("AccessDenied"), g.STS_REJECTION_CODES), ("rejected", "AccessDenied"))
        self.assertEqual(
            g.classify_rejection(self.FakeClientError("InvalidIdentityToken"), g.STS_REJECTION_CODES),
            ("rejected", "InvalidIdentityToken"),
        )
        self.assertEqual(g.classify_rejection(self.FakeClientError("InvalidIdentityToken"), g.S3_DENIAL_CODES)[0], "inconclusive")
        self.assertEqual(g.classify_rejection(self.FakeClientError("Throttling"), g.S3_DENIAL_CODES)[0], "inconclusive")
        self.assertEqual(g.classify_rejection(ConnectionError("x"), g.S3_DENIAL_CODES), ("inconclusive", "ConnectionError"))


class KeyTests(unittest.TestCase):
    def test_keys(self):
        self.assertTrue(g.PROOF_KEY.startswith(g.PREFIX))
        self.assertFalse(g.OUTSIDE_PREFIX_KEY.startswith(g.PREFIX))
        self.assertNotEqual(g.WRONG_AUDIENCE, g.DEFAULT_AUDIENCE)


if __name__ == "__main__":
    unittest.main()
