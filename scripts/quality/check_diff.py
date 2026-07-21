#!/usr/bin/env python3
"""Scan a unified diff for test-oracle weakening patterns."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from qualitylib import load_json_document, scan_unified_diff


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repository_root())
    parser.add_argument("--diff-file", type=Path)
    parser.add_argument("--base", help="git base revision, for example origin/main")
    parser.add_argument(
        "--owner-approved",
        action="store_true",
        help="allow owner-gated policy, snapshot and protected-deletion changes; trusted workflow only",
    )
    args = parser.parse_args()
    config = load_json_document(args.root / "quality/anti-cheating.yaml")
    impact = load_json_document(args.root / ".goclaw/pr-impact.yaml")
    if args.diff_file:
        diff_text = args.diff_file.read_text(encoding="utf-8")
    else:
        command = ["git", "diff", "--no-ext-diff", "--unified=0"]
        if args.base:
            command.append(f"{args.base}...HEAD")
        result = subprocess.run(command, cwd=args.root, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            print(result.stderr.strip(), file=sys.stderr)
            return result.returncode
        diff_text = result.stdout
    issues = scan_unified_diff(
        diff_text,
        config,
        impact,
        owner_approved=args.owner_approved,
    )
    for issue in issues:
        print(f"ERROR {issue.code} {issue.path}: {issue.message}")
    if issues:
        print(f"anti-cheating scan failed with {len(issues)} issue(s)")
        return 1
    print("anti-cheating diff scan passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
