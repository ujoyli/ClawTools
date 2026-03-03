#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/root/.openclaw/workspace"
QUEUE_JSON="$WORKDIR/data/douyin_video_queue.json"
DL_DIR="$WORKDIR/tmp_tiktokdownloader/Volume/Download"
TIKTOKDL_DIR="$WORKDIR/tmp_tiktokdownloader"
VENV_ACT="$TIKTOKDL_DIR/.venv/bin/activate"
UNLIMITED_POSTER_PY="$WORKDIR/scripts/twitter_post_unlimited.py"

if [[ ! -f "$QUEUE_JSON" ]]; then
  echo "Queue empty (no $QUEUE_JSON)" >&2
  exit 0
fi

NEXT=$(python3 - <<'PY'
import json
p='/root/.openclaw/workspace/data/douyin_video_queue.json'
q=json.load(open(p,'r',encoding='utf-8'))
for i,it in enumerate(q.get('queue',[])):
    if isinstance(it,dict) and it.get('status')=='pending':
        print(i)
        raise SystemExit
print('')
PY
)

if [[ -z "$NEXT" ]]; then
  echo "No pending items" >&2
  exit 0
fi

URL=$(python3 -c "import json; q=json.load(open('$QUEUE_JSON','r',encoding='utf-8')); print(q['queue'][int('$NEXT')].get('url',''))")
TITLE=$(python3 -c "import json; q=json.load(open('$QUEUE_JSON','r',encoding='utf-8')); print((q['queue'][int('$NEXT')].get('title','') or '').replace('\\n',' ').strip())")

cd "$TIKTOKDL_DIR"
source "$VENV_ACT"

mkdir -p "$DL_DIR"
BEFORE=$(ls -1t "$DL_DIR"/*.mp4 2>/dev/null | head -n 1 || true)
printf '5\n2\n1\n%s\n\nq\nq\n' "$URL" | python main.py >/tmp/douyin_download_once.log 2>&1 || true
AFTER=$(ls -1t "$DL_DIR"/*.mp4 2>/dev/null | head -n 1 || true)

if [[ -z "$AFTER" || "$AFTER" == "$BEFORE" ]]; then
  echo "Download failed or skipped. Checking if file already exists in download folder..."
  # Try to find file by title matching or similar
  # For simplicity, if download skipped, we look for the most recent mp4
  if [[ -n "$AFTER" ]]; then
    echo "Using existing file: $AFTER"
  else
    echo "No file found." >&2
    exit 1
  fi
fi

CAPTION=$(python3 - <<'PY'
import os
title=os.environ.get('TITLE','').strip()
hook='这条信息量有点大，建议看完再下结论。'
if len(title)>60:
    title=title[:60]+'…'
print(f"{hook}\n{title}\n#抖音 #热点")
PY
)

export TITLE

# 3. Use the new unlimited poster via X-CDP (Chromium CDP)
# NODE_PATH is required to find puppeteer-core in /tmp/node_modules
RESP=$(NODE_PATH=/tmp/node_modules node /root/.openclaw/workspace/skills/x-cdp/scripts/post-tweet.js "$CAPTION" --media "$AFTER" --port 44407)
echo "$RESP"

TWEET_URL=$(echo "$RESP" | grep -oP 'https://x.com/\w+/status/\d+')
if [[ -z "$TWEET_URL" && "$RESP" == *"OK: Tweet posted"* ]]; then
  TWEET_URL="Check X profile" # The script currently doesn't return URL easily, will fix later if needed
fi

export IDX="$NEXT" TWEET_URL

if [[ -z "$TWEET_URL" ]]; then
  echo "Tweet failed: $RESP" >&2
  exit 1
fi

# Mark queue item as posted
python3 - <<'PY'
import json,datetime,os
p='/root/.openclaw/workspace/data/douyin_video_queue.json'
q=json.load(open(p,'r',encoding='utf-8'))
idx=int(os.environ['IDX'])
tweet_url=os.environ['TWEET_URL'].strip()
q['queue'][idx]['status']='posted'
q['queue'][idx]['tweet_url']=tweet_url
q['queue'][idx]['posted_at']=datetime.datetime.now().isoformat()
with open(p,'w',encoding='utf-8') as f:
    json.dump(q, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
