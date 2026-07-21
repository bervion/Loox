#!/usr/bin/env python3
"""Dependency-free validation primitives for the Vaultify quality ledger."""

from __future__ import annotations

import fnmatch
import functools
import hashlib
import json
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STATUS_VALUES = {"known", "verified", "stale", "blocked"}
ID_PATTERNS = {
    "surface_id": re.compile(r"^SURF-[A-Z0-9]+-[0-9]{3}$"),
    "state_id": re.compile(r"^STATE-[A-Z0-9-]+$"),
    "transition_id": re.compile(r"^TRANS-[A-Z0-9-]+$"),
    "journey_id": re.compile(r"^[a-z][a-z0-9-]+$"),
    "fixture_id": re.compile(r"^FIX-[A-Z0-9-]+$"),
    "evidence_id": re.compile(r"^EVID-[A-Z0-9-]+$"),
}
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*['\"]?[A-Za-z0-9_./+-]{16,}"),
    re.compile(r"(?i)\brecovery[_ -]?key\s*[:=]\s*['\"]?[A-Za-z0-9-]{16,}"),
)
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


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    message: str
    path: str

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message, "path": self.path}


def load_json_document(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}:{exc.lineno}:{exc.colno}: not JSON-compatible YAML: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{path}: document root must be an object")
    return value


def _parse_utc(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a UTC offset")
    return parsed.astimezone(timezone.utc)


def _safe_relative_path(root: Path, value: str) -> Path | None:
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts:
        return None
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def _git_sha(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def _git_output(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=root, text=True, capture_output=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def recovery_reference_is_current(
    root: Path, summary: dict[str, Any], tested_sha: str
) -> bool:
    """Reject recovery evidence when its previous-version tag has moved."""

    previous_tag = str(summary.get("previous_tag", ""))
    previous_sha = str(summary.get("previous_sha", ""))
    if not re.fullmatch(
        r"v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9A-Za-z.-]+)?", previous_tag
    ):
        return False
    if not re.fullmatch(r"[0-9a-f]{40}", previous_sha):
        return False
    if not re.fullmatch(r"[0-9a-f]{40}", tested_sha) or previous_sha == tested_sha:
        return False

    current_tag_sha = _git_output(
        root, "rev-parse", f"refs/tags/{previous_tag}^{{commit}}"
    )
    if current_tag_sha != previous_sha:
        return False

    ancestry = subprocess.run(
        ["git", "merge-base", "--is-ancestor", previous_sha, tested_sha],
        cwd=root,
        capture_output=True,
        check=False,
    )
    return ancestry.returncode == 0


def _strip_evidence_promotion_fields(path: str, value: Any) -> Any:
    """Retain behavior semantics while ignoring later evidence/status promotion fields."""

    if path == "quality/coverage-ledger/freshness.yaml" and isinstance(value, dict):
        value = dict(value)
        value["records"] = []
    if isinstance(value, dict):
        return {
            key: _strip_evidence_promotion_fields(path, item)
            for key, item in sorted(value.items())
            if key not in {"verification_status", "evidence_ids"}
        }
    if isinstance(value, list):
        return [_strip_evidence_promotion_fields(path, item) for item in value]
    return value


def evidence_input_digest(root: Path, revision: str) -> str:
    """Hash tracked behavior/test inputs at a git revision, excluding proof metadata only."""

    resolved = _git_output(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    if not resolved:
        return ""
    return _evidence_input_digest_cached(str(root.resolve()), resolved)


@functools.lru_cache(maxsize=32)
def _evidence_input_digest_cached(root_value: str, revision: str) -> str:
    """Compute one revision digest with two git processes, then cache it.

    `git show REV:path` in a per-file loop makes validation O(evidence × files)
    processes. A recursive tree listing plus `git cat-file --batch` preserves
    the same raw-blob semantics without honoring `.gitattributes` archive
    exclusions/substitutions and without a subprocess storm.
    """

    root = Path(root_value)
    tree = subprocess.run(
        ["git", "ls-tree", "-rz", "--full-tree", revision],
        cwd=root,
        capture_output=True,
        check=False,
    )
    if tree.returncode != 0:
        return ""
    entries: list[tuple[str, bytes, bytes]] = []
    for raw_entry in tree.stdout.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata, raw_path = raw_entry.split(b"\t", 1)
            _mode, object_type, object_id = metadata.split(b" ", 2)
            path = raw_path.decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return ""
        if object_type not in {b"blob", b"commit"}:
            return ""
        entries.append((path, object_type, object_id))

    digest = hashlib.sha256()
    excluded_globs = (
        "quality/verification/evidence-index.yaml",
        "quality/verification/evidence/**",
        "quality/generated/**",
        "quality/release/readiness.yaml",
    )
    structured_promotion_paths = {
        "quality/coverage-ledger/surfaces.yaml",
        "quality/coverage-ledger/states.yaml",
        "quality/coverage-ledger/transitions.yaml",
        "quality/coverage-ledger/freshness.yaml",
        "quality/journeys/journeys.yaml",
        "quality/visual-matrix.yaml",
    }
    selected = [
        entry
        for entry in entries
        if not any(fnmatch.fnmatch(entry[0], pattern) for pattern in excluded_globs)
    ]
    blob_ids = [object_id for _path, object_type, object_id in selected if object_type == b"blob"]
    process = subprocess.Popen(
        ["git", "cat-file", "--batch"],
        cwd=root,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    process.stdin.write(b"".join(object_id + b"\n" for object_id in blob_ids))
    process.stdin.close()

    for path, object_type, object_id in selected:
        if any(fnmatch.fnmatch(path, pattern) for pattern in excluded_globs):
            continue
        if object_type == b"commit":
            # A gitlink has no blob; bind its referenced commit identity.
            content = b"Subproject commit " + object_id + b"\n"
        else:
            header = process.stdout.readline().rstrip(b"\n").split(b" ")
            if len(header) != 3 or header[0] != object_id or header[1] != b"blob":
                process.kill()
                process.wait()
                return ""
            try:
                size = int(header[2])
            except ValueError:
                process.kill()
                process.wait()
                return ""
            content = process.stdout.read(size)
            if len(content) != size or process.stdout.read(1) != b"\n":
                process.kill()
                process.wait()
                return ""
        if path in structured_promotion_paths:
            try:
                document = json.loads(content.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                process.kill()
                process.wait()
                return ""
            normalized = _strip_evidence_promotion_fields(path, document)
            content = json.dumps(
                normalized, sort_keys=True, separators=(",", ":"), ensure_ascii=False
            ).encode("utf-8")
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(content)
        digest.update(b"\0")
    if process.wait() != 0:
        return ""
    return digest.hexdigest() if entries else ""


class QualityValidator:
    """Validate contracts and cross-file references without third-party packages."""

    def __init__(self, root: Path, now: datetime | None = None):
        self.root = root.resolve()
        self.now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        self.issues: list[ValidationIssue] = []
        self.documents: dict[str, dict[str, Any]] = {}
        self.indexes: dict[str, dict[str, dict[str, Any]]] = {}

    def add(self, code: str, message: str, path: str) -> None:
        self.issues.append(ValidationIssue(code, message, path))

    def load(self, relative: str) -> dict[str, Any]:
        try:
            document = load_json_document(self.root / relative)
        except ValueError as exc:
            self.add("DOCUMENT", str(exc), relative)
            return {}
        self.documents[relative] = document
        if document.get("schema_version") != 1:
            self.add("SCHEMA_VERSION", "schema_version must equal 1", relative)
        return document

    def _require_path(self, value: str, owner: str, code: str = "PATH") -> None:
        resolved = _safe_relative_path(self.root, value)
        if resolved is None:
            self.add(code, f"path must be repository-relative and cannot escape the root: {value}", owner)
        elif not resolved.exists():
            self.add(code, f"referenced path does not exist: {value}", owner)

    def _make_index(
        self, records: Any, key: str, owner: str, pattern_name: str
    ) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        if not isinstance(records, list):
            self.add("TYPE", f"{key.removesuffix('_id')} records must be an array", owner)
            return result
        pattern = ID_PATTERNS[pattern_name]
        for offset, record in enumerate(records):
            record_path = f"{owner}#{offset}"
            if not isinstance(record, dict):
                self.add("TYPE", "record must be an object", record_path)
                continue
            identifier = record.get(key)
            if not isinstance(identifier, str) or not pattern.fullmatch(identifier):
                self.add("ID_FORMAT", f"invalid {key}: {identifier!r}", record_path)
                continue
            if identifier in result:
                self.add("DUPLICATE_ID", f"duplicate {key}: {identifier}", record_path)
            else:
                result[identifier] = record
        self.indexes[key] = result
        return result

    def _validate_status(self, record: dict[str, Any], owner: str) -> None:
        status = record.get("verification_status")
        evidence = record.get("evidence_ids")
        if status not in STATUS_VALUES:
            self.add("STATUS", f"unsupported verification_status: {status!r}", owner)
        if not isinstance(evidence, list) or not all(isinstance(item, str) for item in evidence):
            self.add("EVIDENCE_IDS", "evidence_ids must be an array of IDs", owner)
            return
        if status == "verified" and not evidence:
            self.add("UNPROVEN_VERIFIED", "verified records require evidence_ids", owner)

    def validate(self, diff_text: str | None = None) -> list[ValidationIssue]:
        project = self.load("quality/project.yaml")
        manifest = self.load(".goclaw/project.yaml")
        impact = self.load(".goclaw/pr-impact.yaml")

        if project.get("project_id") != manifest.get("project_id"):
            self.add("PROJECT_ID", "project IDs differ between manifests", "quality/project.yaml")
        if manifest.get("adapter") != "apple-tuist" or project.get("adapter") != "apple-tuist":
            self.add("ADAPTER", "Vaultify must use the apple-tuist adapter", ".goclaw/project.yaml")
        for source_name, source_path in project.get("sources", {}).items():
            if isinstance(source_path, str):
                self._require_path(source_path, f"quality/project.yaml#sources.{source_name}", "SOURCE_REF")
            else:
                self.add("SOURCE_REF", f"sources.{source_name} must be a repository-relative path", "quality/project.yaml")
        authority = manifest.get("authority", {})
        for field in ("approvers", "merge_authorities", "release_authorities"):
            if authority.get(field) != ["bervion"]:
                self.add("AUTHORITY", f"{field} must contain only bervion", ".goclaw/project.yaml")

        ledger = project.get("ledger", {})
        expected = {
            "surfaces": "quality/coverage-ledger/surfaces.yaml",
            "states": "quality/coverage-ledger/states.yaml",
            "transitions": "quality/coverage-ledger/transitions.yaml",
            "freshness": "quality/coverage-ledger/freshness.yaml",
            "journeys": "quality/journeys/journeys.yaml",
            "fixtures": "quality/fixture-registry.yaml",
            "evidence": "quality/verification/evidence-index.yaml",
        }
        for key, default in expected.items():
            if not isinstance(ledger.get(key), str):
                self.add("LEDGER_CONFIG", f"missing ledger path: {key}", "quality/project.yaml")
            elif ledger[key] != default:
                self.add("LEDGER_CONFIG", f"unexpected ledger path for {key}: {ledger[key]}", "quality/project.yaml")

        surfaces_doc = self.load(expected["surfaces"])
        states_doc = self.load(expected["states"])
        transitions_doc = self.load(expected["transitions"])
        journeys_doc = self.load(expected["journeys"])
        fixtures_doc = self.load(expected["fixtures"])
        evidence_doc = self.load(expected["evidence"])
        freshness_doc = self.load(expected["freshness"])
        app_map = self.load("quality/app-map.yaml")
        visual = self.load("quality/visual-matrix.yaml")
        risks = self.load("quality/risk-register.yaml")
        operations = self.load("quality/release/operations.yaml")
        anti = self.load("quality/anti-cheating.yaml")
        self.load("quality/release/readiness.yaml")

        surfaces = self._make_index(surfaces_doc.get("surfaces"), "surface_id", expected["surfaces"], "surface_id")
        states = self._make_index(states_doc.get("states"), "state_id", expected["states"], "state_id")
        transitions = self._make_index(transitions_doc.get("transitions"), "transition_id", expected["transitions"], "transition_id")
        journeys = self._make_index(journeys_doc.get("journeys"), "journey_id", expected["journeys"], "journey_id")
        fixtures = self._make_index(fixtures_doc.get("fixtures"), "fixture_id", expected["fixtures"], "fixture_id")
        evidence = self._make_index(evidence_doc.get("evidence"), "evidence_id", expected["evidence"], "evidence_id")

        for surface_id, record in surfaces.items():
            owner = f"{expected['surfaces']}#{surface_id}"
            self._validate_status(record, owner)
            if not isinstance(record.get("name"), str) or not record["name"].strip():
                self.add("SURFACE_NAME", "surface name is required", owner)
            if record.get("kind") not in {"screen", "sheet", "flow", "extension", "system-prompt"}:
                self.add("SURFACE_KIND", f"unsupported surface kind: {record.get('kind')!r}", owner)
            if not isinstance(record.get("entry_points"), list) or not record["entry_points"]:
                self.add("ENTRY_POINTS", "surface requires at least one entry point", owner)
            refs = record.get("source_refs")
            if not isinstance(refs, list) or not refs:
                self.add("SOURCE_REF", "surface requires at least one source_refs path", owner)
            else:
                for source in refs:
                    if isinstance(source, str):
                        self._require_path(source, owner, "SOURCE_REF")
                    else:
                        self.add("SOURCE_REF", "source_refs entries must be strings", owner)
            if record.get("verification_status") != "known" and not record.get("evidence_ids"):
                self.add("IMPORTED_STATUS", "non-known imported surface requires evidence", owner)

        for state_id, record in states.items():
            owner = f"{expected['states']}#{state_id}"
            self._validate_status(record, owner)
            if not isinstance(record.get("name"), str) or not record["name"].strip():
                self.add("STATE_NAME", "state name is required", owner)
            if not isinstance(record.get("critical"), bool):
                self.add("CRITICAL_FLAG", "critical must be boolean", owner)
            if record.get("surface_id") not in surfaces:
                self.add("STATE_SURFACE_REF", f"unknown surface_id: {record.get('surface_id')}", owner)
            fixture_ids = record.get("fixture_ids")
            if not isinstance(fixture_ids, list):
                self.add("FIXTURE_IDS", "fixture_ids must be an array", owner)
                fixture_ids = []
            for fixture_id in fixture_ids:
                if fixture_id not in fixtures:
                    self.add("STATE_FIXTURE_REF", f"unknown fixture_id: {fixture_id}", owner)
            if record.get("critical") is True and not fixture_ids:
                self.add("CRITICAL_FIXTURE", "critical state must declare a deterministic fixture", owner)

        for transition_id, record in transitions.items():
            owner = f"{expected['transitions']}#{transition_id}"
            self._validate_status(record, owner)
            if not isinstance(record.get("name"), str) or not record["name"].strip() or not isinstance(record.get("trigger"), str) or not record["trigger"].strip():
                self.add("TRANSITION_CONTRACT", "transition requires a name and observable trigger", owner)
            if not isinstance(record.get("critical"), bool):
                self.add("CRITICAL_FLAG", "critical must be boolean", owner)
            for field in ("from_state_id", "to_state_id"):
                if record.get(field) not in states:
                    self.add("TRANSITION_STATE_REF", f"unknown {field}: {record.get(field)}", owner)

        for journey_id, record in journeys.items():
            owner = f"{expected['journeys']}#{journey_id}"
            self._validate_status(record, owner)
            if not isinstance(record.get("name"), str) or not record["name"].strip():
                self.add("JOURNEY_NAME", "journey name is required", owner)
            if not isinstance(record.get("critical"), bool):
                self.add("CRITICAL_FLAG", "critical must be boolean", owner)
            transition_ids = record.get("transition_ids")
            if not isinstance(transition_ids, list) or not transition_ids:
                self.add("JOURNEY_TRANSITIONS", "journey requires transition_ids", owner)
                transition_ids = []
            chain: list[dict[str, Any]] = []
            for transition_id in transition_ids:
                transition = transitions.get(transition_id)
                if transition is None:
                    self.add("JOURNEY_TRANSITION_REF", f"unknown transition_id: {transition_id}", owner)
                else:
                    chain.append(transition)
            for left, right in zip(chain, chain[1:]):
                if left.get("to_state_id") != right.get("from_state_id"):
                    self.add("JOURNEY_CHAIN", f"transition chain breaks between {left.get('transition_id')} and {right.get('transition_id')}", owner)
            journey_fixture_ids = record.get("fixture_ids")
            if not isinstance(journey_fixture_ids, list):
                self.add("FIXTURE_IDS", "fixture_ids must be an array", owner)
                journey_fixture_ids = []
            for fixture_id in journey_fixture_ids:
                if fixture_id not in fixtures:
                    self.add("JOURNEY_FIXTURE_REF", f"unknown fixture_id: {fixture_id}", owner)
            if record.get("critical") is True and not journey_fixture_ids:
                self.add("CRITICAL_FIXTURE", "critical journey must declare a deterministic fixture", owner)

        for fixture_id, record in fixtures.items():
            owner = f"{expected['fixtures']}#{fixture_id}"
            if record.get("kind") not in {"json-vector", "swift-test-factory", "ui-seed", "service-stub"}:
                self.add("FIXTURE_KIND", f"unsupported fixture kind: {record.get('kind')!r}", owner)
            if record.get("data_classification") != "synthetic":
                self.add("FIXTURE_CLASSIFICATION", "fixtures must be synthetic", owner)
            if record.get("deterministic") is not True:
                self.add("FIXTURE_DETERMINISM", "fixtures must declare deterministic=true", owner)
            if record.get("contains_secrets") is not False:
                self.add("FIXTURE_SECRETS", "fixtures must declare contains_secrets=false", owner)
            path = record.get("path")
            if isinstance(path, str):
                self._require_path(path, owner, "FIXTURE_PATH")
            else:
                self.add("FIXTURE_PATH", "fixture path must be a string", owner)

        self._validate_evidence(evidence, surfaces, states, transitions, journeys, project)
        self._validate_evidence_references(surfaces, states, transitions, journeys, evidence)
        self._validate_freshness(freshness_doc, evidence)
        self._validate_app_map(app_map, surfaces)
        self._validate_visual_matrix(visual, surfaces, states, evidence)
        self._validate_risks(risks, surfaces, states, evidence)
        self._validate_release_operations(operations)
        self._validate_pr_impact(impact, surfaces, states, transitions, anti)
        self._validate_schemas()
        compiled_patterns = self._compile_anti_patterns(anti)
        if diff_text is not None:
            self.issues.extend(scan_unified_diff(diff_text, anti, impact, compiled_patterns))
        self._validate_generated_report(project)
        return sorted(self.issues, key=lambda item: (item.path, item.code, item.message))

    def _validate_evidence(
        self,
        evidence: dict[str, dict[str, Any]],
        surfaces: dict[str, dict[str, Any]],
        states: dict[str, dict[str, Any]],
        transitions: dict[str, dict[str, Any]],
        journeys: dict[str, dict[str, Any]],
        project: dict[str, Any],
    ) -> None:
        evidence_root = project.get("verification", {}).get("evidence_root", "quality/verification/evidence")
        current_sha = _git_sha(self.root)
        for evidence_id, record in evidence.items():
            owner = f"quality/verification/evidence-index.yaml#{evidence_id}"
            try:
                captured_at = _parse_utc(record.get("captured_at", ""))
            except (TypeError, ValueError) as exc:
                self.add("EVIDENCE_TIMESTAMP", f"invalid captured_at: {exc}", owner)
                captured_at = None
            tested_sha = record.get("tested_sha")
            tested_tree = record.get("tested_tree")
            tested_input_digest = record.get("tested_input_digest")
            if not isinstance(tested_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", tested_sha):
                self.add("EVIDENCE_SHA", "tested_sha must be a full lowercase commit SHA", owner)
            if not isinstance(tested_tree, str) or not re.fullmatch(r"[0-9a-f]{40}", tested_tree):
                self.add("EVIDENCE_TREE", "tested_tree must be a full lowercase git tree SHA", owner)
            if not isinstance(tested_input_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", tested_input_digest):
                self.add("EVIDENCE_INPUT_DIGEST", "tested_input_digest must be a lowercase SHA-256", owner)
            if (
                current_sha
                and isinstance(tested_sha, str)
                and re.fullmatch(r"[0-9a-f]{40}", tested_sha)
            ):
                ancestor = subprocess.run(
                    ["git", "merge-base", "--is-ancestor", tested_sha, current_sha],
                    cwd=self.root,
                    capture_output=True,
                    check=False,
                )
                if ancestor.returncode != 0:
                    self.add("EVIDENCE_SHA", "tested_sha must be an ancestor of the evidence commit", owner)
                else:
                    actual_tree = _git_output(self.root, "rev-parse", f"{tested_sha}^{{tree}}")
                    if actual_tree and tested_tree != actual_tree:
                        self.add("EVIDENCE_TREE", "tested_tree does not match tested_sha", owner)
                    tested_digest = evidence_input_digest(self.root, tested_sha)
                    current_digest = evidence_input_digest(self.root, current_sha)
                    if tested_digest and tested_input_digest != tested_digest:
                        self.add(
                            "EVIDENCE_INPUT_DIGEST",
                            "tested_input_digest does not match tested_sha inputs",
                            owner,
                        )
                    if not tested_digest or not current_digest or tested_digest != current_digest:
                        self.add(
                            "EVIDENCE_INPUT_DRIFT",
                            "behavior, production or test inputs changed after tested_sha",
                            owner,
                        )
            claims = record.get("claims")
            allowed_claims = {
                "GATE-LEDGER", "GATE-TESTS", "GATE-PRIVACY",
                "GATE-LOCALIZATION", "GATE-ROLLBACK", "GATE-RISKS",
                "GATE-OPERATIONS",
            }
            if not isinstance(claims, list) or not claims or any(
                claim not in allowed_claims for claim in claims
            ):
                self.add("EVIDENCE_CLAIMS", "claims must name one or more supported release gates", owner)
            attestations = record.get("ci_attestations")
            if not isinstance(attestations, list) or not attestations:
                self.add("EVIDENCE_ATTESTATION", "ci_attestations must be a non-empty array", owner)
                attestations = []
            attested_sources: dict[str, set[tuple[str, str, str]]] = {}
            attested_payloads: dict[str, set[str]] = {}
            for attestation in attestations:
                if not isinstance(attestation, dict):
                    self.add("EVIDENCE_ATTESTATION", "ci_attestations entries must be objects", owner)
                    continue
                required_attestation = {
                    "provider": "github-actions",
                    "repository": "bervion/Vaultify",
                    "conclusion": "success",
                }
                if any(attestation.get(field) != value for field, value in required_attestation.items()):
                    self.add("EVIDENCE_ATTESTATION", "CI provider, repository and conclusion must be trusted constants", owner)
                if attestation.get("head_sha") != tested_sha:
                    self.add("EVIDENCE_ATTESTATION", "CI head_sha must equal tested_sha", owner)
                for field in ("run_id", "run_attempt"):
                    if not isinstance(attestation.get(field), int) or attestation[field] <= 0:
                        self.add("EVIDENCE_ATTESTATION", f"ci_attestation.{field} must be a positive integer", owner)
                workflow = attestation.get("workflow_path")
                if not isinstance(workflow, str) or not workflow.startswith(".github/workflows/") or workflow.endswith("release-ios.yml"):
                    self.add("EVIDENCE_ATTESTATION", "CI evidence must come from a non-release workflow", owner)
                if not isinstance(attestation.get("job_name"), str) or not attestation["job_name"].strip():
                    self.add("EVIDENCE_ATTESTATION", "CI evidence requires a job_name", owner)
                gate_id = attestation.get("gate_id")
                artifact_name = attestation.get("artifact_name")
                if isinstance(gate_id, str) and isinstance(workflow, str) and isinstance(attestation.get("job_name"), str) and isinstance(artifact_name, str):
                    prefix = artifact_name.removesuffix(str(attestation.get("run_attempt")))
                    attested_sources.setdefault(gate_id, set()).add((workflow, attestation["job_name"], prefix))
                    if isinstance(attestation.get("payload_sha256"), str):
                        attested_payloads.setdefault(gate_id, set()).add(attestation["payload_sha256"])
                if not isinstance(attestation.get("artifact_id"), int) or attestation["artifact_id"] <= 0:
                    self.add("EVIDENCE_ATTESTATION", "Actions artifact_id must be a positive integer", owner)
                for field in ("artifact_name", "payload_path"):
                    if not isinstance(attestation.get(field), str) or not attestation[field].strip():
                        self.add("EVIDENCE_ATTESTATION", f"ci_attestation.{field} is required", owner)
                if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(attestation.get("artifact_digest", ""))):
                    self.add("EVIDENCE_ATTESTATION", "Actions artifact_digest must be sha256:<hex>", owner)
                if not re.fullmatch(r"[0-9a-f]{64}", str(attestation.get("payload_sha256", ""))):
                    self.add("EVIDENCE_ATTESTATION", "Actions payload_sha256 must be lowercase SHA-256", owner)
            if isinstance(claims, list):
                for claim in claims:
                    required_sources = GATE_REQUIRED_ATTESTATIONS.get(claim, set())
                    if not required_sources.issubset(attested_sources.get(claim, set())):
                        self.add("EVIDENCE_ATTESTATION", f"{claim} lacks its required trusted workflow jobs", owner)
            if record.get("independent") is not True or record.get("verifier") in (None, "", "coder"):
                self.add("EVIDENCE_INDEPENDENCE", "evidence requires an independent non-coder verifier", owner)
            for field in ("tool", "environment", "redaction", "covers"):
                if not isinstance(record.get(field), dict):
                    self.add("EVIDENCE_METADATA", f"{field} must be an object", owner)
            tool = record.get("tool") if isinstance(record.get("tool"), dict) else {}
            for field in ("name", "version", "command"):
                if not isinstance(tool.get(field), str) or not tool[field].strip():
                    self.add("EVIDENCE_TOOL", f"tool.{field} is required", owner)
            environment = record.get("environment") if isinstance(record.get("environment"), dict) else {}
            for field in ("os", "xcode", "device", "locale", "appearance"):
                if not isinstance(environment.get(field), str) or not environment[field].strip():
                    self.add("EVIDENCE_ENVIRONMENT", f"environment.{field} is required", owner)
            redaction = record.get("redaction") if isinstance(record.get("redaction"), dict) else {}
            if redaction.get("reviewed") is not True or redaction.get("contains_user_data") is not False or not redaction.get("method"):
                self.add("EVIDENCE_REDACTION", "redaction must be reviewed, user-data-free and describe its method", owner)
            covers = record.get("covers") if isinstance(record.get("covers"), dict) else {}
            for key, index in (("surfaces", surfaces), ("states", states), ("transitions", transitions), ("journeys", journeys)):
                values = covers.get(key, [])
                if not isinstance(values, list):
                    self.add("EVIDENCE_COVERAGE", f"covers.{key} must be an array", owner)
                else:
                    for value in values:
                        if value not in index:
                            self.add("EVIDENCE_COVERAGE", f"covers.{key} references unknown ID: {value}", owner)
            artifacts = record.get("artifacts")
            if not isinstance(artifacts, list) or not artifacts:
                self.add("EVIDENCE_ARTIFACT", "evidence requires at least one artifact", owner)
                continue
            artifact_kinds: set[str] = set()
            for artifact in artifacts:
                if not isinstance(artifact, dict):
                    self.add("EVIDENCE_ARTIFACT", "artifact must be an object", owner)
                    continue
                path_value = artifact.get("path")
                kind = artifact.get("kind")
                if not isinstance(kind, str) or not kind:
                    self.add("EVIDENCE_ARTIFACT_KIND", "artifact.kind is required", owner)
                else:
                    artifact_kinds.add(kind)
                resolved = _safe_relative_path(self.root, path_value) if isinstance(path_value, str) else None
                if resolved is None:
                    self.add("EVIDENCE_ARTIFACT", f"invalid artifact path: {path_value!r}", owner)
                    continue
                try:
                    resolved.relative_to((self.root / evidence_root).resolve())
                except ValueError:
                    self.add("EVIDENCE_ARTIFACT", f"artifact must live under {evidence_root}: {path_value}", owner)
                if not resolved.is_file():
                    self.add("EVIDENCE_ARTIFACT", f"artifact does not exist: {path_value}", owner)
                    continue
                payload = resolved.read_bytes()
                digest = hashlib.sha256(payload).hexdigest()
                if artifact.get("sha256") != digest:
                    self.add("EVIDENCE_DIGEST", f"artifact SHA-256 mismatch: {path_value}", owner)
                if len(payload) <= 2_000_000:
                    text = payload.decode("utf-8", errors="ignore")
                    if any(pattern.search(text) for pattern in SECRET_PATTERNS):
                        self.add("EVIDENCE_SECRET", f"artifact matches a prohibited secret pattern: {path_value}", owner)
                if kind in GATE_ARTIFACT_KINDS.values():
                    try:
                        summary = json.loads(payload)
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        self.add("EVIDENCE_GATE_RESULT", f"gate artifact must be JSON: {path_value}", owner)
                        continue
                    if not isinstance(summary, dict) or summary.get("status") != "pass" or summary.get("tested_sha") != tested_sha:
                        self.add("EVIDENCE_GATE_RESULT", f"gate artifact must pass and bind tested_sha: {path_value}", owner)
                    elif kind == "coverage-ledger-report" and summary.get("critical_verified_percent") != 100:
                        self.add("EVIDENCE_GATE_RESULT", "ledger artifact requires 100% critical verification", owner)
                    elif kind == "test-summary" and (
                        summary.get("failed") != 0
                        or any(not isinstance(summary.get(field), int) or summary[field] <= 0 for field in ("unit_passed", "snapshot_passed", "ui_passed", "maestro_passed"))
                    ):
                        self.add("EVIDENCE_GATE_RESULT", "test artifact requires passing unit/snapshot/UI/Maestro suites", owner)
                    elif kind == "privacy-audit" and (
                        summary.get("production_side_effect_findings") != 0
                        or summary.get("executable_privacy_audit_verified") is not True
                    ):
                        self.add("EVIDENCE_GATE_RESULT", "privacy artifact requires promoted executable no-side-effect/redaction receipts", owner)
                    elif kind == "localization-matrix" and (
                        summary.get("missing") != 0
                        or summary.get("accessibility_cases_unverified") != 0
                        or not isinstance(summary.get("locales"), list)
                        or not {"en", "vi"}.issubset(set(summary.get("locales", [])))
                    ):
                        self.add("EVIDENCE_GATE_RESULT", "localization artifact requires complete non-empty en/vi copy and verified accessibility matrix", owner)
                    elif kind == "recovery-rehearsal":
                        if (
                            summary.get("recovery_mode") != "previous-source-fix-forward"
                            or summary.get("production_downgrade_supported") is not False
                            or summary.get("candidate_bootstrap_verified") is not True
                            or summary.get("retained_container_verified") is not True
                            or summary.get("fix_forward_build_verified") is not True
                            or summary.get("process_launch_observed") is not True
                            or summary.get("recovery_relaunch_verified") is not True
                            or summary.get("vault_data_compatibility_verified") is not True
                            or summary.get("functional_unlock_read_verified") is not True
                            or not recovery_reference_is_current(
                                self.root, summary, tested_sha
                            )
                        ):
                            self.add("EVIDENCE_GATE_RESULT", "recovery artifact requires immutable-tag ancestry plus functional unlock/read of candidate-format encrypted vault data", owner)
                    elif kind == "risk-disposition-report" and (
                        summary.get("open_critical_high") != 0
                        or summary.get("invalid_dispositions") != 0
                    ):
                        self.add("EVIDENCE_GATE_RESULT", "risk artifact requires zero open critical/high risks and valid dispositions", owner)
                    elif kind == "release-operations-plan" and (
                        summary.get("release_notes_verified") is not True
                        or summary.get("monitoring_plan_verified") is not True
                        or summary.get("approved_by") != "bervion"
                    ):
                        self.add("EVIDENCE_GATE_RESULT", "operations artifact requires release notes and owner-approved monitoring", owner)
            if isinstance(claims, list):
                for claim in claims:
                    required_kind = GATE_ARTIFACT_KINDS.get(claim)
                    if required_kind and required_kind not in artifact_kinds:
                        self.add("EVIDENCE_GATE_ARTIFACT", f"{claim} requires artifact kind {required_kind}", owner)
                    artifact_digests = {
                        artifact.get("sha256") for artifact in artifacts
                        if isinstance(artifact, dict) and artifact.get("kind") == required_kind
                    }
                    if required_kind and not artifact_digests.intersection(attested_payloads.get(claim, set())):
                        self.add("EVIDENCE_GATE_ARTIFACT", f"{claim} artifact is not byte-bound to its Actions payload", owner)
            if captured_at is not None and captured_at > self.now:
                self.add("EVIDENCE_TIMESTAMP", "captured_at cannot be in the future", owner)

    def _validate_evidence_references(
        self,
        surfaces: dict[str, dict[str, Any]],
        states: dict[str, dict[str, Any]],
        transitions: dict[str, dict[str, Any]],
        journeys: dict[str, dict[str, Any]],
        evidence: dict[str, dict[str, Any]],
    ) -> None:
        for kind, index, coverage_key in (
            ("surface", surfaces, "surfaces"),
            ("state", states, "states"),
            ("transition", transitions, "transitions"),
            ("journey", journeys, "journeys"),
        ):
            for identifier, record in index.items():
                for evidence_id in record.get("evidence_ids", []):
                    proof = evidence.get(evidence_id)
                    if proof is None:
                        self.add("EVIDENCE_REF", f"unknown evidence_id: {evidence_id}", f"{kind}#{identifier}")
                    elif identifier not in proof.get("covers", {}).get(coverage_key, []):
                        self.add("EVIDENCE_REF", f"{evidence_id} does not declare coverage for {identifier}", f"{kind}#{identifier}")

    def _validate_freshness(self, document: dict[str, Any], evidence: dict[str, dict[str, Any]]) -> None:
        policy = document.get("policy", {})
        for field in ("default_max_age_days", "critical_max_age_days"):
            if not isinstance(policy.get(field), int) or policy[field] <= 0:
                self.add("FRESHNESS_POLICY", f"{field} must be a positive integer", "quality/coverage-ledger/freshness.yaml")
        records = document.get("records")
        if not isinstance(records, list):
            self.add("FRESHNESS_RECORD", "records must be an array", "quality/coverage-ledger/freshness.yaml")
            return
        seen: set[str] = set()
        for record in records:
            if not isinstance(record, dict):
                self.add("FRESHNESS_RECORD", "freshness record must be an object", "quality/coverage-ledger/freshness.yaml")
                continue
            evidence_id = record.get("evidence_id")
            if evidence_id in seen:
                self.add("DUPLICATE_ID", f"duplicate freshness evidence_id: {evidence_id}", "quality/coverage-ledger/freshness.yaml")
            seen.add(evidence_id)
            if evidence_id not in evidence:
                self.add("FRESHNESS_EVIDENCE_REF", f"unknown evidence_id: {evidence_id}", "quality/coverage-ledger/freshness.yaml")

        default_age = policy.get("default_max_age_days", 7)
        critical_age = policy.get("critical_max_age_days", 3)
        critical_ids = {
            identifier
            for key in ("state_id", "transition_id", "journey_id")
            for identifier, record in self.indexes.get(key, {}).items()
            if record.get("critical") is True
        }
        verified_evidence_ids = {
            evidence_id
            for key in ("surface_id", "state_id", "transition_id", "journey_id")
            for record in self.indexes.get(key, {}).values()
            if record.get("verification_status") == "verified"
            for evidence_id in record.get("evidence_ids", [])
        }
        for evidence_id, record in evidence.items():
            try:
                captured = _parse_utc(record["captured_at"])
            except (KeyError, TypeError, ValueError):
                continue
            covered = record.get("covers", {})
            covered_ids = set().union(*(covered.get(key, []) for key in ("states", "transitions", "journeys")))
            max_age = critical_age if covered_ids & critical_ids else default_age
            age_seconds = (self.now - captured).total_seconds()
            if evidence_id in verified_evidence_ids and age_seconds > max_age * 86400:
                self.add("STALE_EVIDENCE", f"{evidence_id} is older than {max_age} days", "quality/verification/evidence-index.yaml")

    def _validate_app_map(self, document: dict[str, Any], surfaces: dict[str, dict[str, Any]]) -> None:
        features = document.get("features")
        if not isinstance(features, list):
            self.add("APP_MAP", "features must be an array", "quality/app-map.yaml")
            return
        seen: set[str] = set()
        mapped: set[str] = set()
        for feature in features:
            feature_id = feature.get("feature_id") if isinstance(feature, dict) else None
            if not isinstance(feature_id, str) or not re.fullmatch(r"FEAT-[A-Z0-9]+-[0-9]{3}", feature_id):
                self.add("APP_MAP_ID", f"invalid feature_id: {feature_id!r}", "quality/app-map.yaml")
            elif feature_id in seen:
                self.add("DUPLICATE_ID", f"duplicate feature_id: {feature_id}", "quality/app-map.yaml")
            seen.add(feature_id)
            for surface_id in feature.get("surface_ids", []):
                if surface_id not in surfaces:
                    self.add("APP_MAP_REF", f"unknown surface_id: {surface_id}", "quality/app-map.yaml")
                mapped.add(surface_id)
        missing = set(surfaces) - mapped
        if missing:
            self.add("APP_MAP_COVERAGE", f"surfaces missing from app map: {', '.join(sorted(missing))}", "quality/app-map.yaml")

    def _validate_visual_matrix(
        self,
        document: dict[str, Any],
        surfaces: dict[str, dict[str, Any]],
        states: dict[str, dict[str, Any]],
        evidence: dict[str, dict[str, Any]],
    ) -> None:
        axes = document.get("axes", {})
        cases = document.get("required_cases")
        if not isinstance(cases, list):
            self.add("VISUAL_MATRIX", "required_cases must be an array", "quality/visual-matrix.yaml")
            return
        seen: set[str] = set()
        for case in cases:
            case_id = case.get("case_id") if isinstance(case, dict) else None
            if case_id in seen:
                self.add("DUPLICATE_ID", f"duplicate visual case: {case_id}", "quality/visual-matrix.yaml")
            seen.add(case_id)
            surface_id, state_id = case.get("surface_id"), case.get("state_id")
            if surface_id not in surfaces:
                self.add("VISUAL_SURFACE_REF", f"unknown surface_id: {surface_id}", "quality/visual-matrix.yaml")
            if state_id not in states or states.get(state_id, {}).get("surface_id") != surface_id:
                self.add("VISUAL_STATE_REF", f"state_id does not belong to surface: {state_id}", "quality/visual-matrix.yaml")
            for axis, allowed in axes.items():
                if case.get(axis) not in allowed:
                    self.add("VISUAL_AXIS", f"{case_id} has unsupported {axis}: {case.get(axis)!r}", "quality/visual-matrix.yaml")
            self._validate_status(case, f"quality/visual-matrix.yaml#{case_id}")
            for evidence_id in case.get("evidence_ids", []):
                if evidence_id not in evidence:
                    self.add("EVIDENCE_REF", f"unknown evidence_id: {evidence_id}", f"quality/visual-matrix.yaml#{case_id}")

    def _validate_risks(
        self,
        document: dict[str, Any],
        surfaces: dict[str, Any],
        states: dict[str, Any],
        evidence: dict[str, dict[str, Any]],
    ) -> None:
        records = document.get("risks")
        if not isinstance(records, list):
            self.add("RISK_REGISTER", "risks must be an array", "quality/risk-register.yaml")
            return
        seen: set[str] = set()
        for risk in records:
            if not isinstance(risk, dict):
                self.add("RISK_REGISTER", "risk entries must be objects", "quality/risk-register.yaml")
                continue
            risk_id = risk.get("risk_id")
            if not isinstance(risk_id, str) or not re.fullmatch(r"RISK-[A-Z0-9]+-[0-9]{3}", risk_id):
                self.add("RISK_ID", f"invalid risk_id: {risk_id!r}", "quality/risk-register.yaml")
            elif risk_id in seen:
                self.add("DUPLICATE_ID", f"duplicate risk_id: {risk_id}", "quality/risk-register.yaml")
            seen.add(risk_id)
            status = risk.get("status")
            if status not in {"open", "mitigated", "accepted"}:
                self.add("RISK_STATUS", f"unsupported risk status: {status!r}", f"risk#{risk_id}")
            if status == "mitigated":
                mitigation_evidence = risk.get("mitigation_evidence_ids")
                if not isinstance(mitigation_evidence, list) or not mitigation_evidence:
                    self.add("RISK_MITIGATION", "mitigated risk requires mitigation_evidence_ids", f"risk#{risk_id}")
                else:
                    for evidence_id in mitigation_evidence:
                        proof = evidence.get(evidence_id)
                        if proof is None or risk_id not in proof.get("risk_ids", []):
                            self.add("RISK_MITIGATION", f"{evidence_id} does not explicitly mitigate {risk_id}", f"risk#{risk_id}")
            if status == "accepted" and (
                risk.get("accepted_by") != "bervion"
                or not isinstance(risk.get("acceptance_rationale"), str)
                or not risk["acceptance_rationale"].strip()
                or not isinstance(risk.get("accepted_at"), str)
            ):
                self.add("RISK_ACCEPTANCE", "accepted risk requires dated bervion acceptance and rationale", f"risk#{risk_id}")
            elif status == "accepted":
                try:
                    accepted_at = _parse_utc(risk["accepted_at"])
                    if accepted_at > self.now:
                        raise ValueError("future acceptance")
                except (TypeError, ValueError):
                    self.add("RISK_ACCEPTANCE", "accepted_at must be a non-future UTC timestamp", f"risk#{risk_id}")
            for surface_id in risk.get("surface_ids", []):
                if surface_id not in surfaces:
                    self.add("RISK_SURFACE_REF", f"unknown surface_id: {surface_id}", f"risk#{risk_id}")
            for state_id in risk.get("state_ids", []):
                if state_id not in states:
                    self.add("RISK_STATE_REF", f"unknown state_id: {state_id}", f"risk#{risk_id}")

    def _validate_release_operations(self, document: dict[str, Any]) -> None:
        owner = "quality/release/operations.yaml"
        status = document.get("status")
        if status not in {"not-evaluated", "ready"}:
            self.add("RELEASE_OPERATIONS", f"unsupported operations status: {status!r}", owner)
        monitoring = document.get("monitoring")
        if not isinstance(monitoring, dict):
            self.add("RELEASE_OPERATIONS", "monitoring must be an object", owner)
            return
        if monitoring.get("owner") != "bervion":
            self.add("RELEASE_OPERATIONS", "post-release monitoring owner must be bervion", owner)
        duration = monitoring.get("duration_hours")
        if not isinstance(duration, int) or not 1 <= duration <= 168:
            self.add("RELEASE_OPERATIONS", "monitoring duration must be 1..168 hours", owner)
        for field in ("metrics", "alerts"):
            if not isinstance(monitoring.get(field), list):
                self.add("RELEASE_OPERATIONS", f"monitoring.{field} must be an array", owner)
        runbook = monitoring.get("rollback_or_fix_forward_runbook")
        if not isinstance(runbook, str):
            self.add("RELEASE_OPERATIONS", "monitoring runbook path is required", owner)
        else:
            self._require_path(runbook, owner, "RELEASE_OPERATIONS")
        if status == "ready":
            release_id = document.get("release_id")
            if not isinstance(release_id, str) or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9A-Za-z.-]+)?", release_id):
                self.add("RELEASE_OPERATIONS", "ready operations require an immutable release_id", owner)
            notes = document.get("release_notes_path")
            if not isinstance(notes, str):
                self.add("RELEASE_OPERATIONS", "ready operations require release_notes_path", owner)
            else:
                self._require_path(notes, owner, "RELEASE_OPERATIONS")
            if not monitoring.get("metrics") or not monitoring.get("alerts") or not monitoring.get("incident_channel"):
                self.add("RELEASE_OPERATIONS", "ready operations require metrics, alerts and incident channel", owner)
            if document.get("approved_by") != "bervion" or not str(document.get("approval_rationale") or "").strip():
                self.add("RELEASE_OPERATIONS", "ready operations require bervion approval and rationale", owner)

    def _validate_pr_impact(
        self,
        impact: dict[str, Any],
        surfaces: dict[str, Any],
        states: dict[str, Any],
        transitions: dict[str, Any],
        anti: dict[str, Any],
    ) -> None:
        owner = ".goclaw/pr-impact.yaml"
        if not re.fullmatch(r"TASK-[0-9]{4}-[0-9]{4}", str(impact.get("task_id", ""))):
            self.add("PR_TASK", "task_id must use TASK-YYYY-NNNN", owner)
        if not impact.get("summary") or not impact.get("changed_scopes"):
            self.add("PR_IMPACT", "summary and changed_scopes are required", owner)
        for key, index in (("surfaces", surfaces), ("states", states), ("transitions", transitions)):
            values = impact.get(key)
            if not isinstance(values, list):
                self.add("PR_IMPACT", f"{key} must be an array", owner)
                continue
            for value in values:
                if value not in index:
                    self.add("PR_IMPACT_REF", f"unknown {key} ID: {value}", owner)
        if not impact.get("surfaces") and not str(impact.get("no_surface_impact_reason", "")).strip():
            self.add("PR_NO_SURFACE_REASON", "PRs with no surface impact must explain why", owner)
        for path_field in ("test_paths", "evidence_paths"):
            values = impact.get(path_field)
            if not isinstance(values, list):
                self.add("PR_PATH", f"{path_field} must be an array", owner)
                continue
            for value in values:
                if isinstance(value, str):
                    self._require_path(value, owner, "PR_PATH")
                else:
                    self.add("PR_PATH", f"{path_field} entries must be strings", owner)
        if impact.get("anti_cheating_exceptions"):
            self.add(
                "ANTI_EXCEPTION",
                "repository-authored anti-cheating exceptions are forbidden; use an exact-head bervion review",
                owner,
            )

    def _validate_schemas(self) -> None:
        for path in sorted((self.root / "quality/schemas").glob("*.schema.json")):
            relative = str(path.relative_to(self.root))
            try:
                document = load_json_document(path)
            except ValueError as exc:
                self.add("SCHEMA_DOCUMENT", str(exc), relative)
                continue
            if document.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
                self.add("SCHEMA_DOCUMENT", "schema must declare draft 2020-12", relative)
            if document.get("type") != "object" or not document.get("title"):
                self.add("SCHEMA_DOCUMENT", "schema requires object type and title", relative)

    def _compile_anti_patterns(self, document: dict[str, Any]) -> list[tuple[str, re.Pattern[str], str]]:
        compiled: list[tuple[str, re.Pattern[str], str]] = []
        records = document.get("patterns")
        if not isinstance(records, list):
            self.add("ANTI_PATTERN", "patterns must be an array", "quality/anti-cheating.yaml")
            return compiled
        seen: set[str] = set()
        for record in records:
            pattern_id = record.get("pattern_id") if isinstance(record, dict) else None
            if not isinstance(pattern_id, str) or not re.fullmatch(r"ANTI-[A-Z0-9-]+", pattern_id):
                self.add("ANTI_PATTERN", f"invalid pattern_id: {pattern_id!r}", "quality/anti-cheating.yaml")
                continue
            if pattern_id in seen:
                self.add("DUPLICATE_ID", f"duplicate anti-cheating pattern: {pattern_id}", "quality/anti-cheating.yaml")
            seen.add(pattern_id)
            try:
                compiled.append((pattern_id, re.compile(record["regex"]), record.get("description", "")))
            except (KeyError, re.error) as exc:
                self.add("ANTI_PATTERN", f"invalid regex for {pattern_id}: {exc}", "quality/anti-cheating.yaml")
        return compiled

    def _validate_generated_report(self, project: dict[str, Any]) -> None:
        report_path = project.get("reports", {}).get("json")
        if not isinstance(report_path, str):
            self.add("REPORT_CONFIG", "reports.json is required", "quality/project.yaml")
            return
        resolved = _safe_relative_path(self.root, report_path)
        if resolved is None or not resolved.exists():
            self.add("GENERATED_REPORT", f"generated coverage report is missing: {report_path}", report_path)
            return
        try:
            report = load_json_document(resolved)
        except ValueError as exc:
            self.add("GENERATED_REPORT", str(exc), report_path)
            return
        expected_digest = source_digest(self.root)
        if report.get("source_digest") != expected_digest:
            self.add("GENERATED_REPORT", "coverage report is stale; run scripts/quality/report.py", report_path)


def scan_unified_diff(
    diff_text: str,
    config: dict[str, Any],
    impact: dict[str, Any],
    compiled: list[tuple[str, re.Pattern[str], str]] | None = None,
    *,
    owner_approved: bool = False,
) -> list[ValidationIssue]:
    """Return findings for prohibited patterns on added diff lines."""

    if compiled is None:
        compiled = []
        for record in config.get("patterns", []):
            try:
                compiled.append((record["pattern_id"], re.compile(record["regex"]), record.get("description", "")))
            except (KeyError, re.error):
                continue
    exclusions = config.get("exclude_paths", [])
    pattern_records = {
        item.get("pattern_id"): item
        for item in config.get("patterns", [])
        if isinstance(item, dict)
    }
    current_path = ""
    issues: list[ValidationIssue] = []
    protected_deletion_globs = config.get("protected_deletion_globs", [])
    protected_policy_globs = config.get("protected_policy_globs", [])
    protected_snapshot_globs = config.get("protected_snapshot_globs", [])
    owner_gated_paths: set[tuple[str, str]] = set()
    for raw_line in diff_text.splitlines():
        if raw_line.startswith("diff --git a/"):
            match = re.match(r"diff --git a/(.+) b/(.+)$", raw_line)
            if match:
                current_path = match.group(2)
                if not owner_approved:
                    if any(fnmatch.fnmatch(current_path, pattern) for pattern in protected_policy_globs):
                        owner_gated_paths.add(("ANTI-POLICY-MODIFICATION", current_path))
                    if any(fnmatch.fnmatch(current_path, pattern) for pattern in protected_snapshot_globs):
                        owner_gated_paths.add(("ANTI-SNAPSHOT-BASELINE", current_path))
            continue
        if raw_line.startswith("deleted file mode"):
            if any(fnmatch.fnmatch(current_path, pattern) for pattern in protected_deletion_globs):
                if not owner_approved:
                    issues.append(ValidationIssue(
                        "ANTI-TEST-DELETION",
                        "Wholesale deletion of a protected test or quality flow requires owner approval.",
                        current_path,
                    ))
            continue
        if raw_line.startswith("+++ "):
            candidate_path = raw_line[4:].removeprefix("b/")
            if candidate_path != "/dev/null":
                current_path = candidate_path
            continue
        if not raw_line.startswith("+") or raw_line.startswith("+++"):
            continue
        if any(fnmatch.fnmatch(current_path, pattern) for pattern in exclusions):
            continue
        line = raw_line[1:]
        for pattern_id, pattern, description in compiled:
            path_globs = pattern_records.get(pattern_id, {}).get("path_globs", ["**"])
            if not any(fnmatch.fnmatch(current_path, glob) for glob in path_globs):
                continue
            if not pattern.search(line):
                continue
            issues.append(ValidationIssue(pattern_id, description, current_path or "<diff>"))
    for code, path in sorted(owner_gated_paths):
        description = (
            "Quality policy/workflow changes require a bervion approval on the exact PR head."
            if code == "ANTI-POLICY-MODIFICATION"
            else "Snapshot baseline changes require a bervion approval on the exact PR head."
        )
        issues.append(ValidationIssue(code, description, path))
    return issues


def source_files(root: Path) -> list[Path]:
    relative_paths = [
        ".goclaw/project.yaml",
        "quality/project.yaml",
        "quality/app-map.yaml",
        "quality/visual-matrix.yaml",
        "quality/risk-register.yaml",
        "quality/anti-cheating.yaml",
        "quality/fixture-registry.yaml",
        "quality/coverage-ledger/surfaces.yaml",
        "quality/coverage-ledger/states.yaml",
        "quality/coverage-ledger/transitions.yaml",
        "quality/coverage-ledger/freshness.yaml",
        "quality/journeys/journeys.yaml",
        "quality/verification/evidence-index.yaml",
    ]
    return [root / path for path in relative_paths]


def source_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in source_files(root):
        relative = str(path.relative_to(root))
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def coverage_summary(root: Path) -> dict[str, Any]:
    surfaces = load_json_document(root / "quality/coverage-ledger/surfaces.yaml")["surfaces"]
    states = load_json_document(root / "quality/coverage-ledger/states.yaml")["states"]
    transitions = load_json_document(root / "quality/coverage-ledger/transitions.yaml")["transitions"]
    journeys = load_json_document(root / "quality/journeys/journeys.yaml")["journeys"]

    def summarize(records: Iterable[dict[str, Any]]) -> dict[str, Any]:
        values = list(records)
        by_status = {status: sum(item.get("verification_status") == status for item in values) for status in sorted(STATUS_VALUES)}
        verified = by_status["verified"]
        total = len(values)
        return {"total": total, "verified": verified, "verification_percent": round((verified / total * 100) if total else 0, 1), "by_status": by_status}

    critical_records = [item for item in states + transitions + journeys if item.get("critical") is True]
    return {
        "surfaces": summarize(surfaces),
        "states": summarize(states),
        "transitions": summarize(transitions),
        "journeys": summarize(journeys),
        "critical": summarize(critical_records),
    }
