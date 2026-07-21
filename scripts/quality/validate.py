#!/usr/bin/env python3
"""Validate the full Vaultify quality contract."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from qualitylib import QualityValidator


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def working_tree_diff(root: Path) -> str:
    pieces: list[str] = []
    for command in (
        ["git", "diff", "--no-ext-diff", "--unified=0"],
        ["git", "diff", "--cached", "--no-ext-diff", "--unified=0"],
    ):
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
        if result.returncode == 0:
            pieces.append(result.stdout)
    return "\n".join(pieces)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="validate all quality contracts")
    parser.add_argument("--root", type=Path, default=repository_root())
    parser.add_argument("--diff-file", type=Path, help="scan a unified diff instead of the working tree")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    parser.add_argument("--skip-diff", action="store_true", help="skip the anti-cheating working-tree diff scan")
    args = parser.parse_args()

    diff_text: str | None
    if args.skip_diff:
        diff_text = None
    elif args.diff_file:
        diff_text = args.diff_file.read_text(encoding="utf-8")
    else:
        diff_text = working_tree_diff(args.root)

    issues = QualityValidator(args.root, now=None).validate(diff_text=diff_text)
    payload = {"status": "pass" if not issues else "fail", "issue_count": len(issues), "issues": [issue.as_dict() for issue in issues]}
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif issues:
        for issue in issues:
            print(f"ERROR {issue.code} {issue.path}: {issue.message}")
        print(f"quality validation failed with {len(issues)} issue(s)")
    else:
        print("quality validation passed")
    return 0 if not issues else 1


if __name__ == "__main__":
    sys.exit(main())
