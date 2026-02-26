#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/root/.config/x-twitter/.env"
REPO_DIR="/root/.openclaw/workspace"
VENV_ACT="/root/.openclaw/workspace/tmp_tiktokdownloader/.venv/bin/activate"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi
if [[ ! -f "$VENV_ACT" ]]; then
  echo "Missing venv: $VENV_ACT" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

cd "$REPO_DIR"
# Use DouK-Downloader venv
# shellcheck disable=SC1090
source "$VENV_ACT"

TOPIC_AND_TEXT=$(python scripts/douyin_hot_word_tweet.py)
# First line contains the topic after the colon
TOPIC=$(echo "$TOPIC_AND_TEXT" | head -n 1 | sed -E 's/.*：//')

IMG_OUT="/root/.openclaw/workspace/tmp/hot_poster.png"
python scripts/douyin_hot_poster.py "$TOPIC" "$IMG_OUT"

node skills/twitter-post/scripts/image_post.js "$IMG_OUT" "$TOPIC_AND_TEXT"
