#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
COOKIE_FILE="/home/browserwing/cookie.json"
DB="$WORKDIR/data/rebang_sent.db"
mkdir -p "$WORKDIR/data"

# 1) pick a hupu url from rebang.today via Playwright (fresh session)
PICK_JSON=$(python3 - <<'PY'
import json, re, sqlite3, time
from playwright.sync_api import sync_playwright

DB='/root/.openclaw/workspace/data/rebang_sent.db'
conn=sqlite3.connect(DB)
conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url TEXT PRIMARY KEY, sent_at INTEGER NOT NULL)')
now=int(time.time())
window=24*3600

def sent_recent(u):
    u=re.sub(r'\?.*$','',re.sub(r'#.*$','',u.strip()))
    row=conn.execute('SELECT sent_at FROM sent_urls WHERE url=?',(u,)).fetchone()
    return bool(row and now-int(row[0])<window)

def extract_items(page):
    return page.evaluate('''() => {
      const out=[]; const seen=new Set();
      for (const a of [...document.querySelectorAll('a[href]')]) {
        const href=(a.href||'').trim();
        const text=(a.textContent||'').trim().replace(/\s+/g,' ');
        if(!href||!text||text.length<8) continue;
        if(!/bbs\.hupu\.com\/\d+\.html/i.test(href)) continue;
        if(seen.has(href)) continue;
        seen.add(href); out.push({url:href,title:text});
      }
      return out.slice(0,50);
    }''')

items=[]
last_err=''
with sync_playwright() as p:
    b=p.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox','--disable-dev-shm-usage'])
    ctx=b.new_context(viewport={'width':1366,'height':900})
    page=ctx.new_page()

    # Try rebang with retries
    for i in range(3):
      try:
        page.goto('https://rebang.today/?tab=hupu', wait_until='domcontentloaded', timeout=70000)
        page.wait_for_timeout(12000 + i*3000)
        items=extract_items(page)
        if items: break
      except Exception as e:
        last_err=str(e)

    # Fallback to hupu list page
    if not items:
      try:
        page.goto('https://bbs.hupu.com/all-gambia', wait_until='domcontentloaded', timeout=70000)
        page.wait_for_timeout(12000)
        items=extract_items(page)
      except Exception as e:
        last_err=str(e)

    b.close()

pick=None
for it in items:
    if not sent_recent(it['url']):
        pick=it; break

if not pick:
    print(json.dumps({'ok':False,'error':'no_unposted_hupu_item','count':len(items),'last_error':last_err}))
else:
    print(json.dumps({'ok':True,'url':pick['url'],'title':pick['title'],'count':len(items)},ensure_ascii=False))
PY
)

echo "$PICK_JSON"
if [[ $(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
  exit 75
fi
URL=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["url"])')
TITLE=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["title"])')

# 2) extract title/body/media from hupu thread-content-detail
DETAIL=$(python3 "$WORKDIR/scripts/get_img_from_hupu.py" "$URL")
if [[ $(echo "$DETAIL" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
  echo "$DETAIL"
  exit 1
fi

H_TITLE=$(echo "$DETAIL" | python3 -c 'import json,sys,re;t=json.loads(sys.stdin.read()).get("title",""); t=re.sub(r"\s*-\s*步行街主干道-虎扑社区$", "", t); t=re.sub(r"\s*-\s*虎扑社区$", "", t); print(t.strip())')
BODY=$(echo "$DETAIL" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("body",""))')
MEDIA=$(echo "$DETAIL" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("saved_media") or "")')

# 3) compose text (title + body + tags, no link)
export H_TITLE BODY
TEXT=$(python3 - <<'PY'
import os,re
title=os.environ.get('H_TITLE','').strip()
body=os.environ.get('BODY','').strip()
body=re.sub(r'\s+',' ',body)
if len(body)>120:
    body=body[:117]+'...'
kws=re.findall(r'[\u4e00-\u9fffA-Za-z0-9]{2,6}', title)[:3]
tags=' '.join('#'+k for k in kws) if kws else '#热榜 #虎扑'
text=f"{title}\n\n{body}\n\n{tags}".strip()
print(text)
PY
)

# If over 140 chars, condense via subagent
if [[ ${#TEXT} -gt 140 ]]; then
  echo "Text too long (${#TEXT}), condensing via subagent..."
  CONDENSE_PROMPT=$(cat <<EOF
请把下面这条推文精简到140字符以内，保留核心信息和标签，语气自然，不要加链接，不要解释：

$TEXT
EOF
)
  C_JSON=$(openclaw agent --session-id x-rebang-condense --thinking minimal --timeout 90 --json --message "$CONDENSE_PROMPT" 2>/tmp/rebang_condense.err || true)
  C_TEXT=$(printf '%s' "$C_JSON" | python3 - <<'PY'
import json,sys
s=sys.stdin.read().strip()
try:
  o=json.loads(s)
  p=o.get('payloads',[])
  if p and p[0].get('text'):
    print((p[0].get('text') or '').strip()); raise SystemExit
  print((o.get('result',{}).get('payloads',[{}])[0].get('text') or '').strip())
except:
  pass
PY
)
  if [[ -n "$C_TEXT" ]]; then
    TEXT="$C_TEXT"
  fi
fi

# hard truncate safeguard
if [[ ${#TEXT} -gt 140 ]]; then
  TEXT="${TEXT:0:137}..."
fi

# 4) post tweet via Playwright
if [[ -n "$MEDIA" ]]; then
  POST=$(python3 "$WORKDIR/scripts/PostTweet_PW.py" --cookie-file "$COOKIE_FILE" --text "$TEXT" --media "$MEDIA")
else
  POST=$(python3 "$WORKDIR/scripts/PostTweet_PW.py" --cookie-file "$COOKIE_FILE" --text "$TEXT")
fi
echo "$POST"
if [[ $(echo "$POST" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
  exit 1
fi

# 5) mark sent
export URL
python3 - <<'PY'
import sqlite3, time, os, re
u=os.environ['URL']
u=re.sub(r'\?.*$','',re.sub(r'#.*$','',u.strip()))
conn=sqlite3.connect('/root/.openclaw/workspace/data/rebang_sent.db')
conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url TEXT PRIMARY KEY, sent_at INTEGER NOT NULL)')
conn.execute('INSERT INTO sent_urls(url,sent_at) VALUES(?,?) ON CONFLICT(url) DO UPDATE SET sent_at=excluded.sent_at',(u,int(time.time())))
conn.commit();conn.close()
print('marked sent')
PY

# 6) report
openclaw message send --channel discord --target channel:1476191544808837192 --message "✅ 脚本: rebang_home_hot_image_tweet_pw.sh\nURL: $URL\n媒体: ${MEDIA:-无}\n正文预览: ${TEXT:0:120}" >/dev/null 2>&1 || true

echo "Done"