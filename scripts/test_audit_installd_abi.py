#!/usr/bin/env python3
"""Offline tests for the IInstalld ABI report. No Android or root needed."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("audit_installd_abi", HERE / "audit_installd_abi.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AbiAuditTest(unittest.TestCase):
    def setUp(self):
        # Actual saved Galaxy A05 table from this repository (not a live read).
        table = (HERE.parent / "probe_results" / "host_installd_yaap.txt").read_text(encoding="utf-8")
        self.host = audit.parse_table(table)
        self.reference = dict(self.host)
        self.reference["createFsveritySetupAuthToken"] = (
            53, self.host["createFsveritySetupAuthToken"][1]
        )
        self.reference["enableFsverity"] = (54, self.host["enableFsverity"][1])

    def test_known_a05_fsverity_codes_are_different(self):
        report = audit.audit(self.reference, self.host, 37, 37)
        self.assertEqual("proxy_remap_candidate", report["status"])
        self.assertEqual(27, report["methods_compared"])
        self.assertEqual(25, report["direct"])
        self.assertEqual(2, report["code_shifts"])
        self.assertEqual(0, report["missing"])
        self.assertEqual(0, report["signature_mismatches"])
        self.assertFalse(report["launch_verified"])
        shifts = {x["method"] for x in report["mapping"] if x["status"] == "code_shift"}
        self.assertEqual({"createFsveritySetupAuthToken", "enableFsverity"}, shifts)

    def test_android15_and_16_sdk_mismatch_never_implies_verified_launch(self):
        for sdk in (35, 36):
            report = audit.audit(self.reference, self.host, 37, sdk)
            self.assertTrue(report["sdk_mismatch"])
            self.assertFalse(report["launch_verified"])

    def test_changed_signature_is_not_a_remappable_transaction(self):
        changed = dict(self.host)
        code, _ = changed["createAppData"]
        changed["createAppData"] = (code, "(I)V")
        report = audit.audit(self.reference, changed)
        self.assertEqual("incompatible_methods", report["status"])
        self.assertEqual(1, report["signature_mismatches"])

    def test_missing_required_call_is_blocking(self):
        changed = dict(self.host)
        changed.pop("createUserData")
        report = audit.audit(self.reference, changed)
        self.assertEqual("incompatible_methods", report["status"])
        self.assertEqual(1, report["missing"])

    def test_rejects_duplicate_methods_and_codes(self):
        with self.assertRaisesRegex(ValueError, "duplicate method"):
            audit.parse_table("foo 1 ()V\nfoo 2 ()V\n")
        with self.assertRaisesRegex(ValueError, "duplicate transaction code"):
            audit.parse_table("foo 1 ()V\nbar 1 ()V\n")

    def test_invalid_tables_fail_closed(self):
        for invalid in ("", "foo 0 ()V", "foo X ()V", "foo 1 not-a-signature", "foo 1 ()V extra"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    audit.parse_table(invalid)

    def test_unchanged_subset_is_not_proof_of_launch(self):
        report = audit.audit(self.host, self.host, 37, 37)
        self.assertEqual("method_subset_matches", report["status"])
        self.assertEqual(27, report["direct"])
        self.assertFalse(report["launch_verified"])


if __name__ == "__main__":
    unittest.main()
