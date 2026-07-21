#!/usr/bin/env python3
"""Fail closed unless the checked-out release SHA has complete independent gates."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import os
import urllib.error
import urllib.request
import urllib.parse
import io
import hashlib
import zipfile
from pathlib import Path
from typing import Any

from qualitylib import QualityValidator, load_json_document


CANONICAL_GATE_IDS = {
    "GATE-OWNER", "GATE-LEDGER", "GATE-TESTS", "GATE-PRIVACY",
    "GATE-LOCALIZATION", "GATE-ROLLBACK", "GATE-RISKS", "GATE-OPERATIONS",
}
GATE_ARTIFACT_KINDS = {
    "GATE-LEDGER": "coverage-ledger-report",
    "GATE-TESTS": "test-summary",
    "GATE-PRIVACY": "privacy-audit",
    "GATE-LOCALIZATION": "localization-matrix",
    "GATE-ROLLBACK": "recovery-rehearsal",
    "GATE-RISKS": "risk-disposition-report",
    "GATE-OPERATIONS": "release-operations-plan",
}
GATE_REQUIRED_ATTESTATIONS = {
    "GATE-LEDGER": {(".github/workflows/ci.yml", "Ledger evidence", "ledger-evidence-receipt-")},
    "GATE-TESTS": {(".github/workflows/ci.yml", "Test evidence", "test-evidence-receipt-")},
    "GATE-PRIVACY": {(".github/workflows/ci.yml", "Privacy contract", "privacy-contract-receipt-")},
    "GATE-LOCALIZATION": {(".github/workflows/ci.yml", "Localization contract", "localization-contract-receipt-")},
    "GATE-ROLLBACK": {(".github/workflows/release-evidence.yml", "Recovery rehearsal", "recovery-rehearsal-receipt-")},
    "GATE-RISKS": {(".github/workflows/ci.yml", "Risk disposition", "risk-disposition-receipt-")},
    "GATE-OPERATIONS": {(".github/workflows/ci.yml", "Release operations", "release-operations-receipt-")},
}
MAX_GATE_ARCHIVE_BYTES = 1_000_000
MAX_GATE_PAYLOAD_BYTES = 256_000


def unsigned_artifact_request(location: str) -> urllib.request.Request:
    parsed = urllib.parse.urlparse(location)
    host = (parsed.hostname or "").lower()
    trusted_host = host.endswith(".blob.core.windows.net") or host.endswith(".actions.githubusercontent.com")
    if parsed.scheme != "https" or not trusted_host or parsed.username or parsed.password:
        raise ValueError("GitHub artifact redirect target is not trusted")
    return urllib.request.Request(location, headers={"User-Agent": "vaultify-release-preflight"})


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def select_referenced_evidence(
    readiness: dict[str, Any],
    evidence: dict[str, dict[str, Any]],
    risk_document: dict[str, Any] | None = None,
) -> dict[str, dict[str, Any]]:
    """Select only evidence needed for this release; history may expire remotely."""
    gates = readiness.get("gates")
    if not isinstance(gates, list):
        return {}
    referenced_ids: set[str] = set()
    for gate in gates:
        if not isinstance(gate, dict) or gate.get("gate_id") == "GATE-OWNER":
            continue
        evidence_ids = gate.get("evidence_ids")
        if not isinstance(evidence_ids, list):
            continue
        referenced_ids.update(item for item in evidence_ids if isinstance(item, str))
    if isinstance(risk_document, dict):
        risks = risk_document.get("risks")
        if isinstance(risks, list):
            for risk in risks:
                if (
                    not isinstance(risk, dict)
                    or risk.get("severity") not in {"critical", "high"}
                    or risk.get("status") != "mitigated"
                ):
                    continue
                mitigation_ids = risk.get("mitigation_evidence_ids")
                if isinstance(mitigation_ids, list):
                    referenced_ids.update(item for item in mitigation_ids if isinstance(item, str))
    return {
        evidence_id: evidence[evidence_id]
        for evidence_id in referenced_ids
        if evidence_id in evidence
    }


def git_head(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def validate_release_policy(
    root: Path,
    evidence: dict[str, dict[str, Any]],
    *,
    release_id: str,
) -> list[str]:
    errors: list[str] = []
    try:
        risk_document = load_json_document(root / "quality/risk-register.yaml")
        operations = load_json_document(root / "quality/release/operations.yaml")
    except ValueError as exc:
        return [str(exc)]
    risks = risk_document.get("risks")
    if not isinstance(risks, list):
        errors.append("risk register must contain a risks array")
        risks = []
    for risk in risks:
        if not isinstance(risk, dict) or risk.get("severity") not in {"critical", "high"}:
            continue
        risk_id = str(risk.get("risk_id", "unknown"))
        status = risk.get("status")
        if status == "open":
            errors.append(f"critical/high release risk remains open: {risk_id}")
        elif status == "mitigated":
            mitigation_ids = risk.get("mitigation_evidence_ids")
            if (
                not isinstance(mitigation_ids, list)
                or not mitigation_ids
                or any(item not in evidence or risk_id not in evidence[item].get("risk_ids", []) for item in mitigation_ids)
            ):
                errors.append(f"mitigated release risk lacks registered evidence: {risk_id}")
        elif status == "accepted":
            if (
                risk.get("accepted_by") != "bervion"
                or not str(risk.get("acceptance_rationale") or "").strip()
                or not str(risk.get("accepted_at") or "").strip()
            ):
                errors.append(f"release risk acceptance is not explicitly bound to bervion: {risk_id}")
        else:
            errors.append(f"release risk has invalid disposition: {risk_id}")

    monitoring = operations.get("monitoring")
    notes_path = operations.get("release_notes_path")
    notes_valid = False
    if isinstance(notes_path, str):
        candidate = (root / notes_path).resolve()
        try:
            candidate.relative_to(root.resolve())
            notes_valid = candidate.is_file() and bool(candidate.read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            notes_valid = False
    if operations.get("status") != "ready" or operations.get("release_id") != release_id:
        errors.append("release operations are not ready for the exact release id")
    if not notes_valid:
        errors.append("release notes are missing, empty or outside the repository")
    if not isinstance(monitoring, dict) or (
        monitoring.get("owner") != "bervion"
        or not monitoring.get("metrics")
        or not monitoring.get("alerts")
        or not monitoring.get("incident_channel")
        or not monitoring.get("rollback_or_fix_forward_runbook")
    ):
        errors.append("post-release monitoring/fix-forward plan is incomplete")
    if operations.get("approved_by") != "bervion" or not str(operations.get("approval_rationale") or "").strip():
        errors.append("release operations lack explicit bervion approval")
    return errors


def validate_gate_contract(
    readiness: dict[str, Any],
    evidence: dict[str, dict[str, Any]],
    *,
    release_id: str,
    owner: str,
    triggering_owner: str,
) -> list[str]:
    errors: list[str] = []
    if not release_id or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9A-Za-z.-]+)?", release_id):
        errors.append("release id must be an immutable vX.Y.Z or vX.Y.Z-beta.* tag")
    if owner != "bervion":
        errors.append("release owner must be bervion")
    if triggering_owner != "bervion":
        errors.append("release triggering owner must be bervion")

    if readiness.get("status") != "candidate-ready":
        errors.append("release readiness status must be candidate-ready")
    if readiness.get("release_id") != release_id:
        errors.append("release readiness release_id must equal the immutable tag")

    gates = readiness.get("gates")
    if not isinstance(gates, list):
        return errors + ["release readiness gates must be an array"]

    gate_ids = [gate.get("gate_id") for gate in gates if isinstance(gate, dict)]
    if len(gates) != len(CANONICAL_GATE_IDS) or set(gate_ids) != CANONICAL_GATE_IDS:
        errors.append("release readiness must contain each canonical gate exactly once and no extras")

    seen: set[Any] = set()
    for gate in gates:
        if not isinstance(gate, dict):
            errors.append("release readiness contains a non-object gate")
            continue
        gate_id = gate.get("gate_id")
        if not isinstance(gate_id, str) or gate_id in seen:
            errors.append(f"invalid or duplicate release gate: {gate_id!r}")
            continue
        seen.add(gate_id)
        if gate.get("required") is not True:
            errors.append(f"canonical release gate must remain required: {gate_id}")
        if gate_id == "GATE-OWNER":
            # Exact owner authorization is supplied by the immutable tag actor
            # and triggering-actor workflow checks, not a self-authored file bit.
            if gate.get("passed") is not False or gate.get("evidence_ids") not in ([], None):
                errors.append("GATE-OWNER must remain externally evaluated, false and evidence-free")
            continue
        if gate.get("passed") is not True:
            errors.append(f"required release gate is not passed: {gate_id}")
        evidence_ids = gate.get("evidence_ids")
        if not isinstance(evidence_ids, list) or not evidence_ids:
            errors.append(f"required release gate has no evidence: {gate_id}")
            continue
        if len(evidence_ids) != len(set(evidence_ids)):
            errors.append(f"release gate contains duplicate evidence IDs: {gate_id}")
        for evidence_id in evidence_ids or []:
            record = evidence.get(evidence_id)
            if record is None:
                errors.append(f"release gate references unknown evidence: {gate_id}:{evidence_id}")
            elif gate_id not in record.get("claims", []):
                errors.append(f"release evidence does not claim this gate: {gate_id}:{evidence_id}")
            else:
                attestations = record.get("ci_attestations")
                if not isinstance(attestations, list) or not attestations:
                    errors.append(f"release evidence lacks CI attestations: {gate_id}:{evidence_id}")
                    attestations = []
                attested_sources: set[tuple[str, str, str]] = set()
                gate_payload_digests: set[str] = set()
                for attestation in attestations:
                    if not isinstance(attestation, dict):
                        errors.append(f"release evidence contains invalid CI attestation: {gate_id}:{evidence_id}")
                        continue
                    if attestation.get("provider") != "github-actions" or attestation.get("repository") != "bervion/Vaultify":
                        errors.append(f"release evidence has invalid CI provider/repository: {gate_id}:{evidence_id}")
                    if not isinstance(attestation.get("run_id"), int) or attestation["run_id"] <= 0:
                        errors.append(f"release evidence has invalid CI run id: {gate_id}:{evidence_id}")
                    if not isinstance(attestation.get("run_attempt"), int) or attestation["run_attempt"] <= 0:
                        errors.append(f"release evidence has invalid CI run attempt: {gate_id}:{evidence_id}")
                    if attestation.get("conclusion") != "success" or attestation.get("head_sha") != record.get("tested_sha"):
                        errors.append(f"release evidence CI result is not successful/exact-head: {gate_id}:{evidence_id}")
                    workflow = attestation.get("workflow_path")
                    if not isinstance(workflow, str) or not workflow.startswith(".github/workflows/") or workflow.endswith("release-ios.yml"):
                        errors.append(f"release evidence has invalid source workflow: {gate_id}:{evidence_id}")
                    if not isinstance(attestation.get("job_name"), str) or not attestation["job_name"].strip():
                        errors.append(f"release evidence has no CI job identity: {gate_id}:{evidence_id}")
                    artifact_name = attestation.get("artifact_name")
                    if attestation.get("gate_id") == gate_id and isinstance(workflow, str) and isinstance(attestation.get("job_name"), str) and isinstance(artifact_name, str):
                        attested_sources.add((workflow, attestation["job_name"], artifact_name.removesuffix(str(attestation.get("run_attempt")))))
                        if isinstance(attestation.get("payload_sha256"), str):
                            gate_payload_digests.add(attestation["payload_sha256"])
                    for field in ("artifact_id",):
                        if not isinstance(attestation.get(field), int) or attestation[field] <= 0:
                            errors.append(f"release evidence has invalid Actions artifact id: {gate_id}:{evidence_id}")
                    for field in ("artifact_name", "payload_path"):
                        if not isinstance(attestation.get(field), str) or not attestation[field].strip():
                            errors.append(f"release evidence has incomplete Actions artifact identity: {gate_id}:{evidence_id}")
                    if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(attestation.get("artifact_digest", ""))):
                        errors.append(f"release evidence has invalid Actions artifact digest: {gate_id}:{evidence_id}")
                    if not re.fullmatch(r"[0-9a-f]{64}", str(attestation.get("payload_sha256", ""))):
                        errors.append(f"release evidence has invalid gate payload digest: {gate_id}:{evidence_id}")
                required_sources = GATE_REQUIRED_ATTESTATIONS.get(gate_id, set())
                if not required_sources.issubset(attested_sources):
                    errors.append(f"release evidence lacks gate-specific trusted jobs: {gate_id}:{evidence_id}")
                required_kind = GATE_ARTIFACT_KINDS.get(gate_id)
                artifact_kinds = {artifact.get("kind") for artifact in record.get("artifacts", []) if isinstance(artifact, dict)}
                if required_kind not in artifact_kinds:
                    errors.append(f"release evidence lacks gate-specific artifact {required_kind}: {gate_id}:{evidence_id}")
                repository_digests = {artifact.get("sha256") for artifact in record.get("artifacts", []) if isinstance(artifact, dict) and artifact.get("kind") == required_kind}
                if not gate_payload_digests.intersection(repository_digests):
                    errors.append(f"release gate artifact is not byte-bound to its Actions payload: {gate_id}:{evidence_id}")

    return errors


def verify_github_attestations(evidence: dict[str, dict[str, Any]]) -> list[str]:
    """Cross-check self-declared receipt metadata against GitHub's Actions API."""
    if not evidence:
        return []
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        return ["GITHUB_TOKEN is required to authenticate release evidence attestations"]
    errors: list[str] = []
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "vaultify-release-preflight",
    }
    run_cache: dict[int, dict[str, Any]] = {}
    jobs_cache: dict[tuple[int, int], dict[str, Any]] = {}
    artifacts_cache: dict[int, dict[str, Any]] = {}
    archive_cache: dict[int, bytes] = {}

    def fetch(path: str) -> dict[str, Any]:
        request = urllib.request.Request(f"https://api.github.com{path}", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.loads(response.read())
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            raise RuntimeError("GitHub Actions attestation lookup failed") from exc

    def fetch_bytes(path: str) -> bytes:
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, response_headers, newurl):  # noqa: ANN001
                return None

        request = urllib.request.Request(f"https://api.github.com{path}", headers=headers)
        try:
            opener = urllib.request.build_opener(NoRedirect)
            with opener.open(request, timeout=20):
                raise RuntimeError("GitHub artifact API did not return a download redirect")
        except urllib.error.HTTPError as redirect:
            if redirect.code not in {302, 303, 307, 308}:
                raise RuntimeError("GitHub Actions artifact download failed") from redirect
            location = redirect.headers.get("Location", "")
        except urllib.error.URLError as exc:
            raise RuntimeError("GitHub Actions artifact download failed") from exc
        try:
            unsigned = unsigned_artifact_request(location)
            with urllib.request.urlopen(unsigned, timeout=60) as response:
                content_length = response.headers.get("Content-Length")
                if content_length and int(content_length) > MAX_GATE_ARCHIVE_BYTES:
                    raise RuntimeError("GitHub Actions gate artifact exceeds the size limit")
                payload = response.read(MAX_GATE_ARCHIVE_BYTES + 1)
                if len(payload) > MAX_GATE_ARCHIVE_BYTES:
                    raise RuntimeError("GitHub Actions gate artifact exceeds the size limit")
                return payload
        except (urllib.error.URLError, ValueError) as exc:
            raise RuntimeError("GitHub Actions artifact download failed") from exc

    for evidence_id, record in evidence.items():
        attestations = record.get("ci_attestations")
        if not isinstance(attestations, list):
            errors.append(f"{evidence_id}: CI attestations are malformed")
            continue
        for attestation in attestations:
            if (
                not isinstance(attestation, dict)
                or not isinstance(attestation.get("run_id"), int)
                or not isinstance(attestation.get("run_attempt"), int)
                or not isinstance(attestation.get("artifact_id"), int)
            ):
                continue
            run_id = attestation["run_id"]
            run_attempt = attestation.get("run_attempt")
            artifact_id = attestation.get("artifact_id")
            try:
                if run_id not in run_cache:
                    run_cache[run_id] = fetch(f"/repos/bervion/Vaultify/actions/runs/{run_id}")
                if (run_id, run_attempt) not in jobs_cache:
                    jobs_cache[(run_id, run_attempt)] = fetch(
                        f"/repos/bervion/Vaultify/actions/runs/{run_id}/attempts/{run_attempt}/jobs?per_page=100"
                    )
                if run_id not in artifacts_cache:
                    artifacts_cache[run_id] = fetch(
                        f"/repos/bervion/Vaultify/actions/runs/{run_id}/artifacts?per_page=100"
                    )
                run = run_cache[run_id]
                jobs = jobs_cache[(run_id, run_attempt)]
                artifacts = artifacts_cache[run_id]
            except RuntimeError as exc:
                errors.append(f"{evidence_id}: {exc}")
                continue
            expected_workflow = attestation.get("workflow_path", "").removeprefix(".github/workflows/")
            actual_path = str(run.get("path", "")).removeprefix(".github/workflows/")
            if (
                run.get("head_sha") != record.get("tested_sha")
                or run.get("conclusion") != "success"
                or run.get("run_attempt") != attestation.get("run_attempt")
                or actual_path != expected_workflow
            ):
                errors.append(f"{evidence_id}: GitHub run does not match attested exact-head workflow success")
            matches = [job for job in jobs.get("jobs", []) if job.get("name") == attestation.get("job_name")]
            if len(matches) != 1 or matches[0].get("conclusion") != "success" or matches[0].get("head_sha") not in (None, record.get("tested_sha")):
                errors.append(f"{evidence_id}: attested GitHub job is missing, ambiguous or unsuccessful")
            artifact_matches = [item for item in artifacts.get("artifacts", []) if item.get("id") == attestation.get("artifact_id") and item.get("name") == attestation.get("artifact_name")]
            if len(artifact_matches) != 1 or artifact_matches[0].get("expired") is True or artifact_matches[0].get("digest") != attestation.get("artifact_digest"):
                errors.append(f"{evidence_id}: Actions artifact identity/digest is missing, expired or mismatched")
                continue
            declared_size = artifact_matches[0].get("size_in_bytes")
            if not isinstance(declared_size, int) or declared_size <= 0 or declared_size > MAX_GATE_ARCHIVE_BYTES:
                errors.append(f"{evidence_id}: Actions gate artifact size is missing or exceeds the limit")
                continue
            try:
                if artifact_id not in archive_cache:
                    archive_cache[artifact_id] = fetch_bytes(
                        f"/repos/bervion/Vaultify/actions/artifacts/{artifact_id}/zip"
                    )
                archive = archive_cache[artifact_id]
                archive_digest = "sha256:" + hashlib.sha256(archive).hexdigest()
                if archive_digest != attestation.get("artifact_digest"):
                    errors.append(f"{evidence_id}: downloaded Actions artifact digest mismatches the API attestation")
                with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
                    matches = [item for item in bundle.infolist() if item.filename == attestation.get("payload_path")]
                    if len(matches) != 1 or matches[0].file_size > MAX_GATE_PAYLOAD_BYTES:
                        raise RuntimeError("Actions gate payload is missing, ambiguous or oversized")
                    payload = bundle.read(matches[0])
                if hashlib.sha256(payload).hexdigest() != attestation.get("payload_sha256"):
                    errors.append(f"{evidence_id}: Actions payload bytes mismatch the release evidence digest")
            except (RuntimeError, KeyError, ValueError, zipfile.BadZipFile):
                errors.append(f"{evidence_id}: Actions artifact payload could not be authenticated")
    return errors


def evaluate(
    root: Path,
    *,
    expected_sha: str,
    release_id: str,
    owner: str,
    triggering_owner: str,
) -> list[str]:
    errors: list[str] = []
    current_sha = git_head(root)
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha) or expected_sha != current_sha:
        errors.append("checked-out HEAD does not equal the requested release SHA")

    issues = QualityValidator(root).validate(diff_text=None)
    errors.extend(f"quality:{issue.code}:{issue.path}" for issue in issues)

    try:
        readiness = load_json_document(root / "quality/release/readiness.yaml")
        evidence_document = load_json_document(root / "quality/verification/evidence-index.yaml")
    except ValueError as exc:
        return errors + [str(exc)]
    evidence = {
        item.get("evidence_id"): item
        for item in evidence_document.get("evidence", [])
        if isinstance(item, dict) and isinstance(item.get("evidence_id"), str)
    }
    contract_errors = validate_gate_contract(
        readiness,
        evidence,
        release_id=release_id,
        owner=owner,
        triggering_owner=triggering_owner,
    )
    errors.extend(contract_errors)
    errors.extend(validate_release_policy(root, evidence, release_id=release_id))
    try:
        risk_document = load_json_document(root / "quality/risk-register.yaml")
    except ValueError:
        risk_document = {}
    errors.extend(verify_github_attestations(
        select_referenced_evidence(readiness, evidence, risk_document)
    ))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repository_root())
    parser.add_argument("--sha", required=True)
    parser.add_argument("--release-id", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--triggering-owner", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    errors = evaluate(
        args.root.resolve(),
        expected_sha=args.sha,
        release_id=args.release_id,
        owner=args.owner,
        triggering_owner=args.triggering_owner,
    )
    payload: dict[str, Any] = {
        "status": "pass" if not errors else "fail",
        "sha": args.sha,
        "release_id": args.release_id,
        "owner": args.owner,
        "triggering_owner": args.triggering_owner,
        "errors": errors,
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
