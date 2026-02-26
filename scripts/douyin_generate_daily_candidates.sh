#!/usr/bin/env bash
set -euo pipefail

# Generate daily candidates (rebang.today) via BrowserWing.

VENV_ACT="/root/.openclaw/workspace/tmp_tiktokdownloader/.venv/bin/activate"
cd /root/.openclaw/workspace
# shellcheck disable=SC1090
source "$VENV_ACT"
python scripts/douyin_rebang_candidates.py
