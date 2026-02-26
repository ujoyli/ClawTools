#!/usr/bin/env bash
set -euo pipefail

# Post exactly ONE queued Douyin video to X.
# - Pops first pending item from data/douyin_video_queue.json
# - Downloads via DouK-Downloader (needs cookies already in settings)
# - Posts via twitter-post/scripts/video_post.js

ENV_FILE="/root/.config/x-twitter/.env"
WORKDIR="/root/.openclaw/workspace"
QUEUE_JSON="$WORKDIR/data/douyin_video_queue.json"
DL_DIR="$WORKDIR/tmp_tiktokdownloader/Volume/Download"
TIKTOKDL_DIR="$WORKDIR/tmp_tiktokdownloader"
VENV_ACT="$TIKTOKDL_DIR/.venv/bin/activate"
VIDEO_POST_JS="$WORKDIR/skills/twitter-post/scripts/video_post.js"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi
if [[ ! -f "$QUEUE_JSON" ]]; then
  echo "Queue empty (no $QUEUE_JSON)" >&2
  exit 0
fi

# Read next pending item
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

# Extract url/title
URL=$(python3 -c "import json; q=json.load(open('$QUEUE_JSON','r',encoding='utf-8')); print(q['queue'][int('$NEXT')].get('url',''))")
TITLE=$(python3 -c "import json; q=json.load(open('$QUEUE_JSON','r',encoding='utf-8')); print((q['queue'][int('$NEXT')].get('title','') or '').replace('\\n',' ').strip())")

if [[ -z "${URL:-}" ]]; then
  echo "Queue item missing url" >&2
  exit 1
fi

# Load Twitter env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

cd "$TIKTOKDL_DIR"
# shellcheck disable=SC1090
source "$VENV_ACT"

mkdir -p "$DL_DIR"
BEFORE=$(ls -1t "$DL_DIR"/*.mp4 2>/dev/null | head -n 1 || true)

# Download ONE video via TUI automation
# Menu path: 5(终端交互模式) -> 2(批量下载链接作品 抖音) -> 1(手动输入) -> URL -> blank to exit link input -> q q
printf '5\n2\n1\n%s\n\nq\nq\n' "$URL" | python main.py >/tmp/douyin_download_once.log 2>&1 || true

AFTER=$(ls -1t "$DL_DIR"/*.mp4 2>/dev/null | head -n 1 || true)

if [[ -z "$AFTER" || "$AFTER" == "$BEFORE" ]]; then
  echo "Download failed or no new file. See /tmp/douyin_download_once.log" >&2
  exit 1
fi

# Compose a punchy caption (keep it short)
CAPTION=$(python3 - <<'PY'
import os
title=os.environ.get('TITLE','').strip()
hook='这条信息量有点大，建议看完再下结论。'
if len(title)>60:
    title=title[:60]+'…'
print(f"{hook}\n{title}\n#抖音 #热点")
PY
)

# Post video
RESP=$(node "$VIDEO_POST_JS" "$AFTER" "$CAPTION")

echo "$RESP"

TWEET_URL=$(python3 - <<'PY' <<<"$RESP"
import json,sys
obj=json.loads(sys.stdin.read() or '{}')
print(obj.get('url') or '')
PY
)

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

