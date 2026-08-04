#!/usr/bin/env python3
"""Merge staged localization keys into Vaultify/Localizable.xcstrings.

Why this exists: the string catalog is a single JSON blob with no merge
semantics, so two agents editing it concurrently corrupt each other's work.
Parallel lanes therefore stage their proposed keys as JSON and one integrator
run folds them in here, once, at the end of a wave.

Staging file shape (one per lane, any name matching strings-*.json):

    {"keys": [
      {"key": "...", "en": "...", "vi": "...", "ja": "...", "context": "..."}
    ]}

Rules:
  - Never overwrite an existing translation. Only fill what is missing.
  - A key with a missing VI value is a bug per CLAUDE.md, so report it.
  - Report JA gaps too; the app ships EN + VI + JA.

Usage:
    python3 scripts/merge-staged-strings.py [staging_dir] [--check-only]
"""
from __future__ import annotations

import glob
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "Vaultify", "Localizable.xcstrings")
DEFAULT_STAGING = os.path.join(
    REPO, "plans", "260804-1037-release-readiness-remediation", "reports"
)


def load_catalog() -> dict:
    with open(CATALOG, encoding="utf-8") as fh:
        return json.load(fh)


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def merge(catalog: dict, staged: list[dict]) -> tuple[int, int, list[str]]:
    strings = catalog["strings"]
    source = catalog.get("sourceLanguage", "en")
    added = 0
    filled = 0
    conflicts: list[str] = []

    for entry in staged:
        key = entry.get("key")
        if not key:
            continue
        record = strings.setdefault(key, {})
        if entry.get("context") and "comment" not in record:
            record["comment"] = entry["context"]
        locs = record.setdefault("localizations", {})

        if key not in strings or not locs:
            added += 1

        # An explicit English value is only stored when the key is not itself
        # the English text, which is how the catalog already treats them.
        en = entry.get("en")
        if en and en != key and source not in locs:
            locs[source] = unit(en)
            filled += 1

        for lang in ("vi", "ja"):
            value = entry.get(lang)
            if not value:
                conflicts.append(f"{key}: staged entry has no {lang} value")
                continue
            existing = locs.get(lang, {}).get("stringUnit", {}).get("value")
            if existing is None:
                locs[lang] = unit(value)
                filled += 1
            elif existing != value:
                # Someone already translated it differently. Keep theirs and say so.
                conflicts.append(
                    f"{key}: {lang} already translated, staged value ignored"
                )

    return added, filled, conflicts


def audit(catalog: dict) -> dict[str, list[str]]:
    """Keys missing a translation the project requires."""
    gaps: dict[str, list[str]] = {"vi": [], "ja": []}
    for key, record in catalog["strings"].items():
        locs = record.get("localizations") or {}
        for lang in ("vi", "ja"):
            value = locs.get(lang, {}).get("stringUnit", {}).get("value")
            if not value:
                gaps[lang].append(key)
    return gaps


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check-only" in sys.argv
    staging_dir = args[0] if args else DEFAULT_STAGING

    catalog = load_catalog()

    if not check_only:
        files = sorted(glob.glob(os.path.join(staging_dir, "strings-*.json")))
        if not files:
            print(f"no staging files in {staging_dir}")
        staged: list[dict] = []
        for path in files:
            with open(path, encoding="utf-8") as fh:
                payload = json.load(fh)
            keys = payload.get("keys", [])
            print(f"  {os.path.basename(path)}: {len(keys)} key(s)")
            staged.extend(keys)

        added, filled, conflicts = merge(catalog, staged)
        print(f"merged: {added} new key(s), {filled} value(s) filled")
        for line in conflicts:
            print(f"  ! {line}")

        with open(CATALOG, "w", encoding="utf-8") as fh:
            json.dump(catalog, fh, ensure_ascii=False, indent=2)
            fh.write("\n")

    gaps = audit(catalog)
    failed = False
    for lang in ("vi", "ja"):
        missing = gaps[lang]
        if missing:
            failed = failed or lang == "vi"
            print(f"\n{len(missing)} key(s) missing {lang}:")
            for key in missing[:20]:
                print(f"  - {key!r}")
            if len(missing) > 20:
                print(f"  … and {len(missing) - 20} more")

    if not gaps["vi"] and not gaps["ja"]:
        print("\nall keys have VI and JA")

    # A missing VI value is a repo-rule bug and fails. JA gaps are reported
    # loudly but do not fail, because the catalog already ships with some.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
