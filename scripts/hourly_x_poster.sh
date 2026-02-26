#!/usr/bin/env bash
set -euo pipefail

# Hourly unified poster:
# - If douyin queue has pending item: post ONE queued video
# - Else: post ONE rebang hot item (image + commentary)

WORKDIR="/root/.openclaw/workspace"
QUEUE_JSON="$WORKDIR/data/douyin_video_queue.json"

has_pending() {
  python3 - <<'PY'
import json, os
p='/root/.openclaw/workspace/data/douyin_video_queue.json'
if not os.path.exists(p):
    print('0'); raise SystemExit
obj=json.load(open(p,'r',encoding='utf-8'))
for it in (obj.get('queue') or []):
    if isinstance(it,dict) and it.get('status')=='pending':
        print('1'); raise SystemExit
print('0')
PY
}

if [[ "$(has_pending)" == "1" ]]; then
  echo "queue: pending -> post video"
  "$WORKDIR/scripts/douyin_post_next_video.sh"
else
  echo "queue: empty -> post rebang"
  "$WORKDIR/scripts/rebang_home_hot_image_tweet.sh"
fi
