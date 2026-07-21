#!/usr/bin/env bash
set -euo pipefail

BASE_REVISION="${1:-}"

python3 scripts/quality/report.py --check
python3 scripts/quality/validate.py --all
python3 -m unittest discover -s scripts/quality/tests

if [[ -n "$BASE_REVISION" ]]; then
  python3 scripts/quality/check_diff.py --base "$BASE_REVISION"
else
  python3 scripts/quality/check_diff.py
fi

git diff --check

