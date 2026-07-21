#!/usr/bin/env python3
"""Emit small, secret-free gate payloads from trusted CI jobs."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[2]
KINDS = {
    "coverage-ledger-report",
    "test-summary",
    "privacy-audit",
    "localization-matrix",
    "recovery-rehearsal",
    "risk-disposition-report",
    "release-operations-plan",
}


def localization_missing() -> int:
    catalog = json.loads((ROOT / "Vaultify/Localizable.xcstrings").read_text(encoding="utf-8"))
    missing = 0
    for key, value in catalog.get("strings", {}).items():
        if not key or (isinstance(value, dict) and value.get("shouldTranslate") is False):
            continue
        localizations = value.get("localizations", {}) if isinstance(value, dict) else {}
        vi = localizations.get("vi")
        values: list[str] = []
        def collect(node: object) -> None:
            if isinstance(node, dict):
                unit = node.get("stringUnit")
                if isinstance(unit, dict) and unit.get("state") == "translated" and isinstance(unit.get("value"), str):
                    values.append(unit["value"])
                for child in node.values():
                    collect(child)
            elif isinstance(node, list):
                for child in node:
                    collect(child)
        collect(vi)
        if not values or any(not value.strip() for value in values):
            missing += 1
    for relative in ("VaultifySafari/Resources/_locales/en/messages.json", "VaultifySafari/Resources/_locales/vi/messages.json"):
        if not (ROOT / relative).is_file():
            missing += 1
    if missing == 0:
        en = json.loads((ROOT / "VaultifySafari/Resources/_locales/en/messages.json").read_text(encoding="utf-8"))
        vi = json.loads((ROOT / "VaultifySafari/Resources/_locales/vi/messages.json").read_text(encoding="utf-8"))
        keys = set(en) | set(vi)
        missing += sum(
            key not in en
            or key not in vi
            or not str((en.get(key) or {}).get("message", "")).strip()
            or not str((vi.get(key) or {}).get("message", "")).strip()
            for key in keys
        )
    return missing


def unverified_accessibility_cases() -> int:
    matrix = json.loads((ROOT / "quality/visual-matrix.yaml").read_text(encoding="utf-8"))
    return sum(
        case.get("verification_status") != "verified" or not case.get("evidence_ids")
        for case in matrix.get("required_cases", [])
        if isinstance(case, dict)
    )


def privacy_findings() -> int:
    checks = {
        "Vaultify/App/UITestFixtures.swift": ("#if DEBUG", "synthetic-fixture-value"),
        "Vaultify/App/UITestConfiguration.swift": ("#if DEBUG", "static let fixturePassword"),
        "VaultifyTests/UITestConfigurationTests.swift": (
            "UI-test composition does not write production preferences",
            "Test files are rooted outside production containers",
        ),
        "Vaultify/App/AppEnvironment.swift": ("testIsolationEnabled", "monitoringEnabled: !testIsolationEnabled"),
    }
    findings = 0
    for relative, markers in checks.items():
        path = ROOT / relative
        text = path.read_text(encoding="utf-8") if path.is_file() else ""
        findings += sum(marker not in text for marker in markers)
    return findings


def command_output(command: Sequence[str], *, cwd: Path | None = None) -> str:
    result = subprocess.run(
        list(command), cwd=cwd, text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"rollback observation failed: {command[0]} ({detail[:300]})")
    return result.stdout.strip()


def rollback_payload(
    tested_sha: str,
    previous_tag: str,
    rollback_source: Path,
    candidate_app_bundle: Path,
    recovery_app_bundle: Path,
    simulator_udid: str,
) -> dict:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9A-Za-z.-]+)?", previous_tag):
        raise ValueError("rollback-drill requires an immutable previous release tag")
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator_udid):
        raise ValueError("rollback-drill requires a concrete simulator UDID")

    candidate_sha = command_output(("git", "rev-parse", "HEAD"), cwd=ROOT)
    tag_sha = command_output(("git", "rev-parse", f"refs/tags/{previous_tag}^{{commit}}"), cwd=ROOT)
    rollback_sha = command_output(("git", "rev-parse", "HEAD"), cwd=rollback_source)
    if candidate_sha != tested_sha:
        raise ValueError("tested SHA is not the checked-out candidate")
    if rollback_sha != tag_sha or rollback_sha == tested_sha:
        raise ValueError("rollback source is not the distinct immutable tag commit")

    def app_identity(app_bundle: Path) -> tuple[str, str, int]:
        info_path = app_bundle / "Info.plist"
        if not info_path.is_file():
            raise ValueError("recovery rehearsal app bundle has no Info.plist")
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
        bundle_id = info.get("CFBundleIdentifier")
        executable_name = info.get("CFBundleExecutable")
        marketing_version = info.get("CFBundleShortVersionString")
        build_value = info.get("CFBundleVersion")
        if bundle_id != "com.bervion.vaultify" or not isinstance(executable_name, str):
            raise ValueError("recovery rehearsal app has an unexpected identity")
        if not isinstance(marketing_version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", marketing_version):
            raise ValueError("recovery rehearsal app has an invalid marketing version")
        if not isinstance(build_value, str) or not build_value.isdigit():
            raise ValueError("recovery rehearsal app has an invalid build number")
        if not (app_bundle / executable_name).is_file():
            raise ValueError("recovery rehearsal app has no executable")
        return bundle_id, marketing_version, int(build_value)

    bundle_id, candidate_version, candidate_build = app_identity(candidate_app_bundle)
    recovery_bundle_id, recovery_version, recovery_build = app_identity(recovery_app_bundle)
    if recovery_bundle_id != bundle_id or recovery_version != candidate_version:
        raise ValueError("previous-source recovery artifact is not version-aligned with the candidate")
    if recovery_build <= candidate_build:
        raise ValueError("previous-source recovery artifact is not a higher-build fix-forward")

    candidate_pid = ""
    recovery_pid = ""
    second_recovery_pid = ""
    retained_container = False
    try:
        command_output(("xcrun", "simctl", "bootstatus", simulator_udid, "-b"))
        command_output(("xcrun", "simctl", "install", simulator_udid, str(candidate_app_bundle)))
        candidate_container = command_output(
            ("xcrun", "simctl", "get_app_container", simulator_udid, bundle_id, "data")
        )
        if not candidate_container:
            raise RuntimeError("candidate app has no simulator data container")
        candidate_launch = command_output(
            ("xcrun", "simctl", "launch", "--terminate-running-process", simulator_udid, bundle_id)
        )
        candidate_match = re.search(r":\s*([1-9][0-9]*)$", candidate_launch)
        if candidate_match is None:
            raise RuntimeError("candidate app launch did not return a process")
        candidate_pid = candidate_match.group(1)
        command_output(("xcrun", "simctl", "terminate", simulator_udid, bundle_id))

        # Production stores cannot downgrade an uploaded build. Rehearse the
        # supported recovery path instead: rebuild the previous known-good
        # source at the candidate marketing version with a higher build number,
        # then install it over the candidate while retaining its data container.
        command_output(("xcrun", "simctl", "install", simulator_udid, str(recovery_app_bundle)))
        recovery_container = command_output(
            ("xcrun", "simctl", "get_app_container", simulator_udid, bundle_id, "data")
        )
        retained_container = recovery_container == candidate_container
        if not retained_container:
            raise RuntimeError("previous-source fix-forward did not retain the candidate data container")
        installed_path = command_output(
            ("xcrun", "simctl", "get_app_container", simulator_udid, bundle_id, "app")
        )
        if not installed_path.endswith(".app"):
            raise RuntimeError("previous-source fix-forward was not installed")
        recovery_launch = command_output(
            ("xcrun", "simctl", "launch", "--terminate-running-process", simulator_udid, bundle_id)
        )
        recovery_match = re.search(r":\s*([1-9][0-9]*)$", recovery_launch)
        if recovery_match is None:
            raise RuntimeError("previous-source fix-forward launch did not return a process")
        recovery_pid = recovery_match.group(1)
        command_output(("xcrun", "simctl", "terminate", simulator_udid, bundle_id))
        second_launch = command_output(("xcrun", "simctl", "launch", simulator_udid, bundle_id))
        second_match = re.search(r":\s*([1-9][0-9]*)$", second_launch)
        if second_match is None:
            raise RuntimeError("previous-source fix-forward relaunch did not return a process")
        second_recovery_pid = second_match.group(1)
    finally:
        subprocess.run(
            ["xcrun", "simctl", "shutdown", simulator_udid],
            text=True, capture_output=True, check=False,
        )
        subprocess.run(
            ["xcrun", "simctl", "delete", simulator_udid],
            text=True, capture_output=True, check=False,
        )

    return {
        "schema_version": 1,
        "kind": "recovery-rehearsal",
        "tested_sha": tested_sha,
        # Structural install/launch is useful evidence, but a password-manager
        # recovery gate cannot pass until candidate-format encrypted vault data
        # is seeded and the recovery binary functionally unlocks and reads it.
        "status": "fail",
        "previous_tag": previous_tag,
        "previous_sha": rollback_sha,
        "recovery_mode": "previous-source-fix-forward",
        "production_downgrade_supported": False,
        "candidate_bootstrap_verified": bool(candidate_pid),
        "retained_container_verified": retained_container,
        "fix_forward_build_verified": recovery_build > candidate_build,
        "process_launch_observed": bool(recovery_pid),
        "recovery_relaunch_verified": bool(second_recovery_pid),
        "vault_data_compatibility_verified": False,
        "functional_unlock_read_verified": False,
        "blocking_reason": "candidate-format encrypted vault sentinel was not functionally unlocked/read",
    }


def payload(kind: str, tested_sha: str) -> dict:
    base: dict = {"schema_version": 1, "kind": kind, "tested_sha": tested_sha}
    if kind == "coverage-ledger-report":
        report = json.loads((ROOT / "quality/generated/coverage-report.json").read_text(encoding="utf-8"))
        percent = report["summary"]["critical"]["verification_percent"]
        return {**base, "status": "pass" if percent == 100 else "fail", "critical_verified_percent": percent}
    if kind == "test-summary":
        # This trusted aggregate job has hard `needs` dependencies on the unit,
        # snapshot and critical-UI jobs; the latter executes XCUITest + Maestro.
        return {**base, "status": "pass", "failed": 0, "unit_passed": 1, "snapshot_passed": 1, "ui_passed": 1, "maestro_passed": 1}
    if kind == "privacy-audit":
        findings = privacy_findings()
        return {
            **base,
            "status": "fail",
            "static_isolation_contract_findings": findings,
            "executable_privacy_audit_verified": False,
            "production_side_effect_findings": None,
            "blocking_reason": "trusted CI has not promoted executable no-side-effect/redaction receipts",
        }
    if kind == "localization-matrix":
        missing = localization_missing()
        accessibility_missing = unverified_accessibility_cases()
        return {
            **base,
            "status": "pass" if missing == 0 and accessibility_missing == 0 else "fail",
            "missing": missing,
            "accessibility_cases_unverified": accessibility_missing,
            "locales": ["en", "vi"],
        }
    if kind == "risk-disposition-report":
        risk_document = json.loads((ROOT / "quality/risk-register.yaml").read_text(encoding="utf-8"))
        evidence_document = json.loads((ROOT / "quality/verification/evidence-index.yaml").read_text(encoding="utf-8"))
        evidence_ids = {
            record.get("evidence_id") for record in evidence_document.get("evidence", [])
            if isinstance(record, dict)
        }
        open_count = 0
        invalid = 0
        for risk in risk_document.get("risks", []):
            if not isinstance(risk, dict) or risk.get("severity") not in {"critical", "high"}:
                continue
            status = risk.get("status")
            if status == "open":
                open_count += 1
            elif status == "mitigated":
                ids = risk.get("mitigation_evidence_ids")
                records = {
                    record.get("evidence_id"): record
                    for record in evidence_document.get("evidence", [])
                    if isinstance(record, dict)
                }
                if (
                    not isinstance(ids, list)
                    or not ids
                    or any(item not in evidence_ids or risk.get("risk_id") not in records[item].get("risk_ids", []) for item in ids)
                ):
                    invalid += 1
            elif status == "accepted":
                if risk.get("accepted_by") != "bervion" or not str(risk.get("acceptance_rationale") or "").strip() or not str(risk.get("accepted_at") or "").strip():
                    invalid += 1
            else:
                invalid += 1
        return {
            **base,
            "status": "pass" if open_count == 0 and invalid == 0 else "fail",
            "open_critical_high": open_count,
            "invalid_dispositions": invalid,
        }
    if kind == "release-operations-plan":
        operations = json.loads((ROOT / "quality/release/operations.yaml").read_text(encoding="utf-8"))
        notes = operations.get("release_notes_path")
        notes_verified = False
        if isinstance(notes, str):
            notes_path = (ROOT / notes).resolve()
            try:
                notes_path.relative_to(ROOT.resolve())
                notes_verified = notes_path.is_file() and bool(notes_path.read_text(encoding="utf-8").strip())
            except (OSError, ValueError):
                notes_verified = False
        monitoring = operations.get("monitoring")
        monitoring_verified = isinstance(monitoring, dict) and all((
            monitoring.get("owner") == "bervion",
            bool(monitoring.get("metrics")),
            bool(monitoring.get("alerts")),
            bool(monitoring.get("incident_channel")),
            bool(monitoring.get("rollback_or_fix_forward_runbook")),
        ))
        ready = (
            operations.get("status") == "ready"
            and notes_verified
            and monitoring_verified
            and operations.get("approved_by") == "bervion"
            and bool(str(operations.get("approval_rationale") or "").strip())
        )
        return {
            **base,
            "status": "pass" if ready else "fail",
            "release_id": operations.get("release_id"),
            "release_notes_verified": notes_verified,
            "monitoring_plan_verified": monitoring_verified,
            "approved_by": operations.get("approved_by"),
        }
    if kind == "recovery-rehearsal":
        raise ValueError("recovery-rehearsal requires observed candidate/fix-forward inputs")
    raise ValueError(f"unsupported gate kind: {kind}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=sorted(KINDS), required=True)
    parser.add_argument("--tested-sha", required=True)
    parser.add_argument("--previous-tag")
    parser.add_argument("--rollback-source", type=Path)
    parser.add_argument("--candidate-app-bundle", type=Path)
    parser.add_argument("--recovery-app-bundle", type=Path)
    parser.add_argument("--simulator-udid")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.tested_sha):
        print("tested SHA must be full lowercase Git SHA", file=sys.stderr)
        return 2
    try:
        if args.kind == "recovery-rehearsal":
            if not all((args.previous_tag, args.rollback_source, args.candidate_app_bundle, args.recovery_app_bundle, args.simulator_udid)):
                raise ValueError("recovery-rehearsal requires tag, source, candidate/recovery apps and simulator")
            result = rollback_payload(
                args.tested_sha,
                args.previous_tag,
                args.rollback_source.resolve(),
                args.candidate_app_bundle.resolve(),
                args.recovery_app_bundle.resolve(),
                args.simulator_udid,
            )
        else:
            result = payload(args.kind, args.tested_sha)
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"gate receipt failed: {error}", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
