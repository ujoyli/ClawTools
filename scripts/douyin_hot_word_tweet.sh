#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/root/.config/x-twitter/.env"
REPO_DIR="/root/.openclaw/workspace"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi

# Load Twitter creds (do not echo)
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

cd "$REPO_DIR"

# Use DouK-Downloader venv (has httpx, etc.)
source /root/.openclaw/workspace/tmp_tiktokdownloader/.venv/bin/activate
TWEET_TEXT=$(python scripts/douyin_hot_word_tweet.py)

node skills/twitter-post/scripts/tweet.js "$TWEET_TEXT"
