from __future__ import annotations

import hashlib
import json
import copy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(SCRIPT_DIR))

from qualitylib import QualityValidator, load_json_document, recovery_reference_is_current, scan_unified_diff  # noqa: E402
from verify_release_readiness import select_referenced_evidence, unsigned_artifact_request, validate_gate_contract, validate_release_policy, verify_github_attestations  # noqa: E402


class QualityValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name)
        shutil.copytree(REPOSITORY_ROOT / "quality", self.root / "quality")
        shutil.copytree(REPOSITORY_ROOT / ".goclaw", self.root / ".goclaw")
        for relative in ("AGENTS.md", "docs/app-feature-map-ui-ux.md", "docs/codebase-summary.md", "docs/design-dna-standard.md"):
            self._copy_placeholder(relative)
        surfaces = load_json_document(self.root / "quality/coverage-ledger/surfaces.yaml")["surfaces"]
        fixtures = load_json_document(self.root / "quality/fixture-registry.yaml")["fixtures"]
        for record in surfaces:
            for relative in record["source_refs"]:
                self._copy_placeholder(relative)
        for record in fixtures:
            self._copy_placeholder(record["path"])
        self._copy_placeholder("scripts/quality/tests/test_quality.py")

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def _copy_placeholder(self, relative: str) -> None:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        source = REPOSITORY_ROOT / relative
        if source.is_file():
            shutil.copyfile(source, target)
        elif not target.exists():
            target.write_text("fixture placeholder\n", encoding="utf-8")

    def _document(self, relative: str) -> dict:
        return load_json_document(self.root / relative)

    def _write(self, relative: str, document: dict) -> None:
        (self.root / relative).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    def _codes(self, now: datetime | None = None) -> set[str]:
        return {issue.code for issue in QualityValidator(self.root, now=now).validate(diff_text="")}

    def test_repository_contract_passes(self) -> None:
        issues = QualityValidator(REPOSITORY_ROOT).validate(diff_text="")
        self.assertEqual([], issues, "\n".join(f"{issue.code}: {issue.message}" for issue in issues))

    def test_duplicate_surface_id_is_rejected(self) -> None:
        document = self._document("quality/coverage-ledger/surfaces.yaml")
        document["surfaces"].append(dict(document["surfaces"][0]))
        self._write("quality/coverage-ledger/surfaces.yaml", document)
        self.assertIn("DUPLICATE_ID", self._codes())

    def test_broken_state_surface_reference_is_rejected(self) -> None:
        document = self._document("quality/coverage-ledger/states.yaml")
        document["states"][0]["surface_id"] = "SURF-NOPE-999"
        self._write("quality/coverage-ledger/states.yaml", document)
        self.assertIn("STATE_SURFACE_REF", self._codes())

    def test_critical_state_requires_fixture(self) -> None:
        document = self._document("quality/coverage-ledger/states.yaml")
        critical = next(record for record in document["states"] if record["critical"])
        critical["fixture_ids"] = []
        self._write("quality/coverage-ledger/states.yaml", document)
        self.assertIn("CRITICAL_FIXTURE", self._codes())

    def test_missing_fixture_path_is_rejected(self) -> None:
        document = self._document("quality/fixture-registry.yaml")
        document["fixtures"][0]["path"] = "fixtures/does-not-exist.json"
        self._write("quality/fixture-registry.yaml", document)
        self.assertIn("FIXTURE_PATH", self._codes())

    def test_verified_record_requires_evidence(self) -> None:
        document = self._document("quality/coverage-ledger/surfaces.yaml")
        document["surfaces"][0]["verification_status"] = "verified"
        self._write("quality/coverage-ledger/surfaces.yaml", document)
        self.assertIn("UNPROVEN_VERIFIED", self._codes())

    def test_stale_evidence_and_secret_artifact_are_rejected(self) -> None:
        artifact = self.root / "quality/verification/evidence/TASK-TEST/result.txt"
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_text("recovery_key=THIS-IS-SYNTHETIC-BUT-MUST-BE-REDACTED\n", encoding="utf-8")
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        evidence = self._document("quality/verification/evidence-index.yaml")
        evidence["evidence"] = [{
            "evidence_id": "EVID-TEST-001",
            "captured_at": "2026-01-01T00:00:00Z",
            "tested_sha": "0" * 40,
            "tested_tree": "0" * 40,
            "tested_input_digest": "0" * 64,
            "verifier": "rex",
            "independent": True,
            "claims": ["GATE-TESTS"],
            "ci_attestations": [{"gate_id": "GATE-TESTS", "provider": "github-actions", "repository": "bervion/Vaultify", "workflow_path": ".github/workflows/ci.yml", "run_id": 1, "run_attempt": 1, "job_name": "Test evidence", "conclusion": "success", "head_sha": "0" * 40, "artifact_id": 1, "artifact_name": "test-evidence-receipt-1", "artifact_digest": "sha256:" + "1" * 64, "payload_path": "test-summary.json", "payload_sha256": digest}],
            "tool": {"name": "xcodebuild", "version": "test", "command": "test"},
            "environment": {"os": "test", "xcode": "test", "device": "test", "locale": "en", "appearance": "light"},
            "artifacts": [{"path": "quality/verification/evidence/TASK-TEST/result.txt", "sha256": digest, "kind": "log"}],
            "redaction": {"reviewed": True, "contains_user_data": False, "method": "synthetic"},
            "covers": {"surfaces": [], "states": ["STATE-LOCK-PASSWORD"], "transitions": [], "journeys": []}
        }]
        self._write("quality/verification/evidence-index.yaml", evidence)
        state_doc = self._document("quality/coverage-ledger/states.yaml")
        state = next(record for record in state_doc["states"] if record["state_id"] == "STATE-LOCK-PASSWORD")
        state["verification_status"] = "verified"
        state["evidence_ids"] = ["EVID-TEST-001"]
        self._write("quality/coverage-ledger/states.yaml", state_doc)
        codes = self._codes(now=datetime(2026, 7, 20, tzinfo=timezone.utc))
        self.assertIn("STALE_EVIDENCE", codes)
        self.assertIn("EVIDENCE_SECRET", codes)

    def test_pr_without_surface_impact_requires_reason(self) -> None:
        impact = self._document(".goclaw/pr-impact.yaml")
        impact["surfaces"] = []
        impact.pop("no_surface_impact_reason", None)
        self._write(".goclaw/pr-impact.yaml", impact)
        self.assertIn("PR_NO_SURFACE_REASON", self._codes())

    def test_anti_cheating_scan_detects_disabled_and_constant_tests(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        diff = """diff --git a/VaultifyTests/UnsafeTests.swift b/VaultifyTests/UnsafeTests.swift
--- a/VaultifyTests/UnsafeTests.swift
+++ b/VaultifyTests/UnsafeTests.swift
@@ -1,0 +1,2 @@
+throw XCTSkip("later")
+XCTAssertTrue(true)
"""
        codes = {issue.code for issue in scan_unified_diff(diff, config, impact)}
        self.assertEqual(
            {"ANTI-DISABLED-TEST", "ANTI-CONSTANT-ASSERT", "ANTI-POLICY-MODIFICATION"},
            codes,
        )

    def test_anti_cheating_scan_detects_snapshot_weakening_and_test_deletion(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        diff = """diff --git a/VaultifySnapshotTests/UnsafeSnapshotTests.swift b/VaultifySnapshotTests/UnsafeSnapshotTests.swift
--- a/VaultifySnapshotTests/UnsafeSnapshotTests.swift
+++ b/VaultifySnapshotTests/UnsafeSnapshotTests.swift
@@ -1,0 +1,2 @@
+assertSnapshot(of: view, as: .image(precision: 0.9), record: .all)
+isRecording = true
diff --git a/VaultifyTests/DeletedTests.swift b/VaultifyTests/DeletedTests.swift
deleted file mode 100644
--- a/VaultifyTests/DeletedTests.swift
+++ /dev/null
@@ -1 +0,0 @@
-XCTAssertTrue(subject.isValid)
"""
        codes = {issue.code for issue in scan_unified_diff(diff, config, impact)}
        self.assertEqual(
            {
                "ANTI-SNAPSHOT-PRECISION", "ANTI-SNAPSHOT-RECORD",
                "ANTI-TEST-DELETION", "ANTI-POLICY-MODIFICATION",
            },
            codes,
        )

    def test_quality_wrapper_cannot_be_replaced_without_exact_head_owner_approval(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        diff = """diff --git a/scripts/ci/run-quality-contract.sh b/scripts/ci/run-quality-contract.sh
--- a/scripts/ci/run-quality-contract.sh
+++ b/scripts/ci/run-quality-contract.sh
@@ -1,3 +1,2 @@
-python3 scripts/quality/validate.py --all
-python3 scripts/quality/report.py --check
+exit 0
"""
        blocked = {issue.code for issue in scan_unified_diff(diff, config, impact)}
        self.assertEqual({"ANTI-POLICY-MODIFICATION"}, blocked)
        self.assertEqual(
            [], scan_unified_diff(diff, config, impact, owner_approved=True)
        )

    def test_repository_declared_exception_cannot_bypass_unsafe_test_change(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        impact["anti_cheating_exceptions"] = [{
            "pattern_id": "ANTI-SNAPSHOT-RECORD",
            "path": "VaultifySnapshotTests/**",
            "reason": "candidate-authored claim",
            "owner_approved_by": "bervion",
            "expires_on": "2099-01-01",
        }]
        diff = """diff --git a/VaultifySnapshotTests/UnsafeTests.swift b/VaultifySnapshotTests/UnsafeTests.swift
--- a/VaultifySnapshotTests/UnsafeTests.swift
+++ b/VaultifySnapshotTests/UnsafeTests.swift
@@ -1,0 +1 @@
+assertSnapshot(of: view, as: .image, record: .all)
"""
        codes = {issue.code for issue in scan_unified_diff(diff, config, impact)}
        self.assertIn("ANTI-SNAPSHOT-RECORD", codes)

    def test_exact_head_owner_approval_only_unlocks_owner_gated_file_changes(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        diff = """diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1,0 +1 @@
+name: Updated CI
diff --git a/VaultifySnapshotTests/__Snapshots__/Control.png b/VaultifySnapshotTests/__Snapshots__/Control.png
new file mode 100644
index 0000000..1111111
Binary files /dev/null and b/VaultifySnapshotTests/__Snapshots__/Control.png differ
diff --git a/VaultifyTests/DeletedTests.swift b/VaultifyTests/DeletedTests.swift
deleted file mode 100644
--- a/VaultifyTests/DeletedTests.swift
+++ /dev/null
"""
        blocked = {issue.code for issue in scan_unified_diff(diff, config, impact)}
        self.assertEqual(
            {"ANTI-POLICY-MODIFICATION", "ANTI-SNAPSHOT-BASELINE", "ANTI-TEST-DELETION"},
            blocked,
        )
        self.assertEqual([], scan_unified_diff(diff, config, impact, owner_approved=True))

    def test_owner_approval_never_allows_oracle_weakening(self) -> None:
        config = self._document("quality/anti-cheating.yaml")
        impact = self._document(".goclaw/pr-impact.yaml")
        diff = """diff --git a/VaultifySnapshotTests/UnsafeTests.swift b/VaultifySnapshotTests/UnsafeTests.swift
--- a/VaultifySnapshotTests/UnsafeTests.swift
+++ b/VaultifySnapshotTests/UnsafeTests.swift
@@ -1,0 +1 @@
+assertSnapshot(of: view, as: .image(precision: 0.8), record: .all)
"""
        codes = {
            issue.code
            for issue in scan_unified_diff(diff, config, impact, owner_approved=True)
        }
        self.assertEqual({"ANTI-SNAPSHOT-PRECISION", "ANTI-SNAPSHOT-RECORD"}, codes)

    def test_recovery_reference_rejects_force_moved_previous_tag(self) -> None:
        def git(*arguments: str) -> str:
            result = subprocess.run(
                ["git", *arguments],
                cwd=self.root,
                text=True,
                capture_output=True,
                check=True,
            )
            return result.stdout.strip()

        git("init")
        git("config", "user.name", "Vaultify Quality Tests")
        git("config", "user.email", "quality-tests@vaultify.invalid")
        marker = self.root / "recovery-marker.txt"
        marker.write_text("previous\n", encoding="utf-8")
        git("add", "recovery-marker.txt")
        git("commit", "-m", "previous")
        previous_sha = git("rev-parse", "HEAD")
        git("tag", "v1.0.0")

        marker.write_text("candidate\n", encoding="utf-8")
        git("add", "recovery-marker.txt")
        git("commit", "-m", "candidate")
        tested_sha = git("rev-parse", "HEAD")
        summary = {"previous_tag": "v1.0.0", "previous_sha": previous_sha}

        self.assertTrue(recovery_reference_is_current(self.root, summary, tested_sha))
        git("tag", "-f", "v1.0.0", tested_sha)
        self.assertFalse(recovery_reference_is_current(self.root, summary, tested_sha))

    def _ready_release_contract(self) -> tuple[dict, dict]:
        claims = [
            "GATE-LEDGER", "GATE-TESTS", "GATE-PRIVACY",
            "GATE-LOCALIZATION", "GATE-ROLLBACK", "GATE-RISKS",
            "GATE-OPERATIONS",
        ]
        evidence = {"EVID-RELEASE-001": {
            "claims": claims,
            "tested_sha": "a" * 40,
            "ci_attestations": [
                {
                    "gate_id": gate, "provider": "github-actions", "repository": "bervion/Vaultify",
                    "workflow_path": workflow, "run_id": run_id, "run_attempt": 1,
                    "job_name": job, "conclusion": "success", "head_sha": "a" * 40,
                    "artifact_id": artifact_id, "artifact_name": prefix + "1",
                    "artifact_digest": "sha256:" + "c" * 64,
                    "payload_path": kind + ".json", "payload_sha256": "b" * 64,
                }
                for artifact_id, (gate, workflow, run_id, job, prefix, kind) in enumerate((
                    ("GATE-LEDGER", ".github/workflows/ci.yml", 123, "Ledger evidence", "ledger-evidence-receipt-", "coverage-ledger-report"),
                    ("GATE-TESTS", ".github/workflows/ci.yml", 123, "Test evidence", "test-evidence-receipt-", "test-summary"),
                    ("GATE-PRIVACY", ".github/workflows/ci.yml", 123, "Privacy contract", "privacy-contract-receipt-", "privacy-audit"),
                    ("GATE-LOCALIZATION", ".github/workflows/ci.yml", 123, "Localization contract", "localization-contract-receipt-", "localization-matrix"),
                    ("GATE-ROLLBACK", ".github/workflows/release-evidence.yml", 456, "Recovery rehearsal", "recovery-rehearsal-receipt-", "recovery-rehearsal"),
                    ("GATE-RISKS", ".github/workflows/ci.yml", 123, "Risk disposition", "risk-disposition-receipt-", "risk-disposition-report"),
                    ("GATE-OPERATIONS", ".github/workflows/ci.yml", 123, "Release operations", "release-operations-receipt-", "release-operations-plan"),
                ), start=1)
            ],
            "artifacts": [
                {"kind": "coverage-ledger-report", "sha256": "b" * 64},
                {"kind": "test-summary", "sha256": "b" * 64},
                {"kind": "privacy-audit", "sha256": "b" * 64},
                {"kind": "localization-matrix", "sha256": "b" * 64},
                {"kind": "recovery-rehearsal", "sha256": "b" * 64},
                {"kind": "risk-disposition-report", "sha256": "b" * 64},
                {"kind": "release-operations-plan", "sha256": "b" * 64},
            ],
        }}
        gates = [{
            "gate_id": "GATE-OWNER",
            "description": "external owner tag",
            "required": True,
            "passed": False,
            "evidence_ids": [],
        }]
        gates.extend({
            "gate_id": gate_id,
            "description": gate_id,
            "required": True,
            "passed": True,
            "evidence_ids": ["EVID-RELEASE-001"],
        } for gate_id in claims)
        return {
            "status": "candidate-ready",
            "release_id": "v1.2.3",
            "gates": gates,
        }, evidence

    def test_release_contract_requires_every_canonical_gate(self) -> None:
        readiness, evidence = self._ready_release_contract()
        readiness["gates"][1]["required"] = False
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="bervion", triggering_owner="bervion",
        )
        self.assertTrue(any("must remain required" in error for error in errors))

    def test_release_contract_rejects_unrelated_evidence_claim(self) -> None:
        readiness, evidence = self._ready_release_contract()
        evidence["EVID-RELEASE-001"]["claims"] = ["GATE-TESTS"]
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="bervion", triggering_owner="bervion",
        )
        self.assertTrue(any("does not claim this gate" in error for error in errors))

    def test_release_contract_rejects_duplicate_or_extra_gates(self) -> None:
        readiness, evidence = self._ready_release_contract()
        readiness["gates"].append(copy.deepcopy(readiness["gates"][1]))
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="bervion", triggering_owner="bervion",
        )
        self.assertTrue(any("exactly once" in error for error in errors))
        self.assertTrue(any("duplicate release gate" in error for error in errors))

    def test_release_contract_requires_owner_and_triggering_owner(self) -> None:
        readiness, evidence = self._ready_release_contract()
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="mallory", triggering_owner="rerunner",
        )
        self.assertIn("release owner must be bervion", errors)
        self.assertIn("release triggering owner must be bervion", errors)

    def test_release_contract_rejects_self_asserted_gate_without_ci_attestation(self) -> None:
        readiness, evidence = self._ready_release_contract()
        evidence["EVID-RELEASE-001"].pop("ci_attestations")
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="bervion", triggering_owner="bervion",
        )
        self.assertTrue(any("lacks CI attestations" in error for error in errors))

    def test_release_contract_rejects_one_successful_job_claiming_every_gate(self) -> None:
        readiness, evidence = self._ready_release_contract()
        evidence["EVID-RELEASE-001"]["ci_attestations"] = [
            evidence["EVID-RELEASE-001"]["ci_attestations"][1]
        ]
        errors = validate_gate_contract(
            readiness, evidence, release_id="v1.2.3",
            owner="bervion", triggering_owner="bervion",
        )
        self.assertTrue(any("gate-specific trusted jobs" in error for error in errors))

    def test_artifact_redirect_drops_github_authorization_header(self) -> None:
        request = unsigned_artifact_request(
            "https://results123.blob.core.windows.net/actions/signed.zip?sig=fixture"
        )
        self.assertIsNone(request.get_header("Authorization"))
        self.assertEqual("vaultify-release-preflight", request.get_header("User-agent"))
        with self.assertRaises(ValueError):
            unsigned_artifact_request("https://attacker.example/artifact.zip")

    def test_release_preflight_ignores_unreferenced_expired_history(self) -> None:
        readiness, current = self._ready_release_contract()
        registry = {
            **current,
            "EVID-EXPIRED-HISTORY": {
                "tested_sha": "0" * 40,
                "ci_attestations": [{"artifact_id": 999, "expired": True}],
            },
        }
        selected = select_referenced_evidence(readiness, registry)
        self.assertEqual({"EVID-RELEASE-001"}, set(selected))

    def test_release_preflight_remotely_selects_mitigation_only_evidence(self) -> None:
        readiness, current = self._ready_release_contract()
        registry = {
            **current,
            "EVID-MITIGATION-ONLY": {
                "risk_ids": ["RISK-SEC-001"],
                "ci_attestations": [{"artifact_id": 999}],
            },
        }
        risks = {
            "risks": [{
                "risk_id": "RISK-SEC-001",
                "severity": "critical",
                "status": "mitigated",
                "mitigation_evidence_ids": ["EVID-MITIGATION-ONLY"],
            }]
        }
        selected = select_referenced_evidence(readiness, registry, risks)
        self.assertEqual({"EVID-RELEASE-001", "EVID-MITIGATION-ONLY"}, set(selected))

    def test_release_preflight_malformed_gate_documents_fail_closed_without_crash(self) -> None:
        self.assertEqual({}, select_referenced_evidence({"gates": None}, {}))
        self.assertEqual({}, select_referenced_evidence({"gates": [{"evidence_ids": None}]}, {}))
        with mock.patch.dict("os.environ", {"GITHUB_TOKEN": "fixture"}):
            errors = verify_github_attestations({"EVID-BROKEN": {"ci_attestations": None}})
        self.assertEqual(["EVID-BROKEN: CI attestations are malformed"], errors)

    def test_release_policy_blocks_open_critical_and_missing_operations(self) -> None:
        errors = validate_release_policy(self.root, {}, release_id="v1.2.3")
        self.assertTrue(any("remains open" in error for error in errors))
        self.assertIn("release operations are not ready for the exact release id", errors)
        self.assertIn("release notes are missing, empty or outside the repository", errors)

    def test_release_policy_rejects_unrelated_mitigation_evidence(self) -> None:
        risks = self._document("quality/risk-register.yaml")
        risks["risks"][0]["status"] = "mitigated"
        risks["risks"][0]["mitigation_evidence_ids"] = ["EVID-UNRELATED"]
        self._write("quality/risk-register.yaml", risks)
        errors = validate_release_policy(
            self.root,
            {"EVID-UNRELATED": {"risk_ids": ["RISK-OTHER-999"]}},
            release_id="v1.2.3",
        )
        self.assertIn("mitigated release risk lacks registered evidence: RISK-SEC-001", errors)


if __name__ == "__main__":
    unittest.main()
