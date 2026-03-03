#!/usr/bin/env bash
set -uo pipefail

WORKDIR="/root/.openclaw/workspace"
QUEUE_JSON="$WORKDIR/data/douyin_video_queue.json"

has_pending() {
  python3 - <<'PY'
import json, os
p='/root/.openclaw/workspace/data/douyin_video_queue.json'
if not os.path.exists(p):
    print('0'); raise SystemExit
try:
    obj=json.load(open(p,'r',encoding='utf-8'))
    for it in (obj.get('queue') or []):
        if isinstance(it,dict) and it.get('status')=='pending':
            print('1'); raise SystemExit
except: pass
print('0')
PY
}

if [[ "$(has_pending)" == "1" ]]; then
  echo "queue: pending -> trying video post"
  if "$WORKDIR/scripts/douyin_post_next_video_unlimited.sh"; then
    echo "Video post success."
    exit 0
  else
    echo "Video post failed or skipped. Falling back to Rebang hot item."
  fi
fi

echo "Running Rebang hot item post (unlimited)..."
"$WORKDIR/scripts/rebang_home_hot_image_tweet_unlimited.sh"
