#!/usr/bin/env bash
set -euo pipefail

# Generate candidates then proactively DM the user on Discord via OpenClaw CLI.
TARGET_DISCORD_ID="1476191544808837192"  # DM channel id for this chat

cd /root/.openclaw/workspace

# 1) Generate candidates file
/root/.openclaw/workspace/scripts/douyin_generate_daily_candidates.sh

MSG_FILE="/root/.openclaw/workspace/data/douyin_candidates.txt"
if [[ ! -s "$MSG_FILE" ]]; then
  echo "No candidates generated" >&2
  exit 1
fi

# 2) Send message
openclaw message send \
  --channel discord \
  --target "$TARGET_DISCORD_ID" \
  --message "$(cat "$MSG_FILE")" \
  --silent \
  --json >/dev/null
