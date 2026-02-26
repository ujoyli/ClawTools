#!/usr/bin/env bash
set -euo pipefail

# Post a "爆款文案 + 海报图" based on rebang.today homepage items (not Douyin).

ENV_FILE="/root/.config/x-twitter/.env"
WORKDIR="/root/.openclaw/workspace"
VENV_ACT="$WORKDIR/tmp_tiktokdownloader/.venv/bin/activate"  # has pillow + httpx

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

cd "$WORKDIR"
# shellcheck disable=SC1090
source "$VENV_ACT"

# Pick Nth item based on hour to reduce repeats
IDX=$(date +%H)
# use 1..10
IDX=$(( (10#${IDX} % 10) + 1 ))

python - <<'PY' > /tmp/rebang_pick.json
import os, json, httpx
BW=os.environ.get('BROWSERWING_URL','http://127.0.0.1:18080')
idx=int(os.environ.get('IDX','1'))

with httpx.Client(headers={'Content-Type':'application/json'}) as c:
    c.post(BW+'/api/v1/executor/navigate', json={'url':'https://rebang.today/','wait_until':'domcontentloaded','timeout':60}, timeout=120).raise_for_status()
    c.post(BW+'/api/v1/executor/wait', json={'identifier':'a[href]','state':'visible','timeout':20}, timeout=30).raise_for_status()
    # Extract a list of headline-like links (dedupe by href, keep longer text)
    script=r"""() => {
  const isJunk = (t) => !t || t.length < 10 || /^\d{2}:\d{2}$/.test(t);
  const map = new Map();
  document.querySelectorAll('a[href]').forEach(a => {
    const href = a.href;
    let txt = (a.textContent||'').trim().replace(/\s+/g,' ');
    if (!href || isJunk(txt)) return;
    if (!map.has(href)) map.set(href, {href, text: ''});
    if (txt.length > map.get(href).text.length) map.get(href).text = txt;
  });
  return Array.from(map.values()).filter(x=>x.text && x.href).slice(0, 30);
}"""
    r=c.post(BW+'/api/v1/executor/evaluate', json={'script':script}, timeout=60)
    r.raise_for_status()
    obj=r.json()
    items=(obj.get('data') or {}).get('result') or []

items=[i for i in items if isinstance(i,dict) and i.get('href') and i.get('text')]
if not items:
    print(json.dumps({'ok':False,'error':'no items'}))
else:
    pick=items[min(idx-1, len(items)-1)]
    print(json.dumps({'ok':True,'idx':idx,'title':pick['text'][:180],'url':pick['href']} , ensure_ascii=False))
PY

PICK=$(cat /tmp/rebang_pick.json)
OK=$(python - <<'PY'
import json
obj=json.loads(open('/tmp/rebang_pick.json','r',encoding='utf-8').read())
print('1' if obj.get('ok') else '0')
PY
)

if [[ "$OK" != "1" ]]; then
  echo "Failed to pick item: $PICK" >&2
  exit 1
fi

TITLE=$(python - <<'PY'
import json
obj=json.loads(open('/tmp/rebang_pick.json','r',encoding='utf-8').read())
print(obj['title'])
PY
)
URL=$(python - <<'PY'
import json
obj=json.loads(open('/tmp/rebang_pick.json','r',encoding='utf-8').read())
print(obj['url'])
PY
)

export TITLE URL

# Generate poster image from title
IMG_OUT="$WORKDIR/tmp/rebang_poster.png"
python scripts/douyin_hot_poster.py "$TITLE" "$IMG_OUT"

# Compose punchy copy
TEXT=$(python - <<'PY'
import os
title=os.environ['TITLE'].strip()
url=os.environ['URL'].strip()
if len(title)>60:
    title=title[:60]+'…'
print(f"别划走，这条信息量很大：\n{title}\n\n{url}\n#今日热榜 #热点")
PY
)

node skills/twitter-post/scripts/image_post.js "$IMG_OUT" "$TEXT"
