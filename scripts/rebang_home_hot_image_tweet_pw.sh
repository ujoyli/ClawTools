#!/usr/bin/env bash
set -euo pipefail
echo "DEBUG: Script starting" >&2
WORKDIR="/root/.openclaw/workspace"
COOKIE_FILE="/home/browserwing/cookie.json"
DB="$WORKDIR/data/rebang_sent.db"
mkdir -p "$WORKDIR/data"
echo "DEBUG: After mkdir" >&2

# Initialize database with skipped_urls table
echo "DEBUG: Before DB init" >&2
python3 - <<'PY'
import sqlite3
conn=sqlite3.connect('/root/.openclaw/workspace/data/rebang_sent.db')
conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url TEXT PRIMARY KEY, sent_at INTEGER NOT NULL)')
conn.execute('CREATE TABLE IF NOT EXISTS skipped_urls (url TEXT PRIMARY KEY, skipped_at INTEGER NOT NULL, reason TEXT)')
conn.commit();conn.close()
PY
echo "DEBUG: After DB init" >&2

# Function to pick a hupu url from rebang.today via Playwright (fresh session)
pick_hupu_url() {
python3 - <<'PY'
import json, re, sqlite3, time
from playwright.sync_api import sync_playwright

DB='/root/.openclaw/workspace/data/rebang_sent.db'
conn=sqlite3.connect(DB)
conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url PRIMARY KEY, sent_at INTEGER NOT NULL)')
conn.execute('CREATE TABLE IF NOT EXISTS skipped_urls (url TEXT PRIMARY KEY, skipped_at INTEGER NOT NULL, reason TEXT)')
now=int(time.time())
window=24*3600

def sent_recent(u):
    u=re.sub(r'\?.*$','',re.sub(r'#.*$','',u.strip()))
    row=conn.execute('SELECT sent_at FROM sent_urls WHERE url=?',(u,)).fetchone()
    if row and now-int(row[0])<window:
        return True
    row=conn.execute('SELECT skipped_at FROM skipped_urls WHERE url=?',(u,)).fetchone()
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
    b=p.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox','--disable-dev-shm-usage','--disable-gpu'])
    ctx=b.new_context(viewport={'width':1366,'height':900})
    page=ctx.new_page()

    try:
      page.goto('https://bbs.hupu.com/all-gambia', wait_until='networkidle', timeout=70000)
      page.wait_for_timeout(10000)
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
}

# Function to mark URL as skipped (no media)
mark_skipped() {
  local url="$1"
  local reason="$2"
  python3 - <<PY
import sqlite3, time, re
u="$url"
u=re.sub(r'\?.*\$','',re.sub(r'#.*\$', '',u.strip()))
conn=sqlite3.connect('/root/.openclaw/workspace/data/rebang_sent.db')
conn.execute('CREATE TABLE IF NOT EXISTS skipped_urls (url TEXT PRIMARY KEY, skipped_at INTEGER NOT NULL, reason TEXT)')
conn.execute('INSERT INTO skipped_urls(url,skipped_at,reason) VALUES(?,?,?) ON CONFLICT(url) DO UPDATE SET skipped_at=excluded.skipped_at,reason=excluded.reason',(u,int(time.time()),"$reason"))
conn.commit();conn.close()
PY
}

# Function to condense text via subagent to <=140 chars
condense_text() {
  local text="$1"
  local result=""
  
  result=$(openclaw agent --session-id x-rebang-condense --thinking minimal --timeout 90 --json --message "请把下面这条推文精简到**140 字符以内**（必须严格遵守），保留核心信息，语气自然流畅：
- 去掉冗余词汇和重复表达
- 保留关键事实和情绪
- 不要加链接
- 不要解释，直接输出精简后的推文

原文：
$text" 2>/tmp/rebang_condense.err || echo "")
  
  if [[ -n "$result" ]]; then
    # Extract text from JSON response
    local extracted=$(RESULT_JSON="$result" python3 - <<'PY'
import json,os
s=(os.environ.get('RESULT_JSON') or '').strip()
try:
  o=json.loads(s)
  # Try different response formats
  payloads=o.get('payloads',[])
  if payloads and len(payloads)>0:
    txt=payloads[0].get('text','')
    if txt:
      print(txt.strip()); raise SystemExit
  result=o.get('result',{})
  payloads=result.get('payloads',[])
  if payloads and len(payloads)>0:
    txt=payloads[0].get('text','')
    if txt:
      print(txt.strip()); raise SystemExit
  # Fallback: return empty
  print('')
except Exception:
  print('')
PY
)
    if [[ -n "$extracted" ]]; then
      echo "$extracted"
      return 0
    fi
  fi
  return 1
}
echo "DEBUG: condense_text defined" >&2

# Main loop: keep trying until we find a postable item
echo "DEBUG: Before main loop" >&2
MAX_ATTEMPTS=10
attempt=0
echo "DEBUG: MAX_ATTEMPTS=$MAX_ATTEMPTS attempt=$attempt" >&2

while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
  ((++attempt))
  echo "DEBUG: Before attempt $attempt" >&2
echo "=== Attempt $attempt / $MAX_ATTEMPTS ==="
  
  # 1) Pick a hupu URL
  PICK_JSON=$(pick_hupu_url)
  echo "$PICK_JSON"
  
  if [[ $(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
    echo "No more unpicked items"
    exit 75
  fi
  
  URL=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["url"])')
  TITLE=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["title"])')
  echo "Selected: $TITLE"
  
  # 2) Extract title/body/media from hupu thread-content-detail
  DETAIL=$(python3 "$WORKDIR/scripts/get_img_from_hupu.py" "$URL")
  if [[ $(echo "$DETAIL" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
    echo "Failed to extract detail: $DETAIL"
    mark_skipped "$URL" "extraction_failed"
    continue
  fi
  
  H_TITLE=$(echo "$DETAIL" | python3 -c 'import json,sys,re; t=json.loads(sys.stdin.read()).get("title","") or ""; # robust cleaning\nt=re.sub(r"\s*-\s*.*?(虎扑|虎扑社区).*?$","",t,flags=re.IGNORECASE)\n# remove explicit mentions\nt=re.sub(r"虎扑社区","",t,flags=re.IGNORECASE)\nt=re.sub(r"虎扑","",t,flags=re.IGNORECASE)\nt=re.sub(r"\s*-\s*步行街.*$","",t,flags=re.IGNORECASE)\nprint(t.strip())')
  BODY=$(echo "$DETAIL" | python3 -c 'import json,sys;print((json.loads(sys.stdin.read()).get("body","") or "").strip())')
  MEDIA=$(echo "$DETAIL" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("saved_media") or "")')

  # 如果抓取标题为空，用列表标题兜底
  if [[ -z "$H_TITLE" ]]; then
    H_TITLE="$TITLE"
  fi

  # Check if media exists - if not, skip and try next
  if [[ -z "$MEDIA" ]]; then
    echo "⚠️ No media found for this post, skipping..."
    mark_skipped "$URL" "no_media"
    continue
  fi
  
  echo "✅ Media found: $MEDIA"
  break
done

# If we exhausted all attempts
if [[ -z "$MEDIA" ]]; then
  echo "❌ Failed to find a postable item after $MAX_ATTEMPTS attempts"
  exit 75
fi

# 3) Compose text
# 规则：
# - 若没抓到正文但有图片：用标题作为正文发布
# - 若抓到正文：标题 + 正文
export H_TITLE BODY
TEXT=$(python3 - <<'PY'
import os,re
title=(os.environ.get('H_TITLE','') or '').strip()
body=(os.environ.get('BODY','') or '').strip()
body=re.sub(r'\s+',' ',body)
if body:
    text=f"{title}\n\n{body}".strip()
else:
    text=title.strip()
print(text)
PY
)

echo "Original text length: ${#TEXT} chars"

# 底线：必须至少有标题文本
if [[ -z "$(printf '%s' "$TEXT" | sed -E 's/[[:space:]]+//g')" ]]; then
  echo "❌ Empty title/body content, abort"
  exit 76
fi

# 4) If over 140 chars, condense via subagent (no hard truncation)
if [[ ${#TEXT} -gt 140 ]]; then
  echo "Text too long (${#TEXT}), condensing via subagent..."

  # Try up to 3 times
  for retry in 1 2 3; do
    C_TEXT=$(condense_text "$TEXT")
    if [[ -n "$C_TEXT" && ${#C_TEXT} -le 140 ]]; then
      TEXT="$C_TEXT"
      echo "✅ Condensed to ${#TEXT} chars"
      break
    elif [[ -n "$C_TEXT" ]]; then
      echo "⚠️ Subagent output still too long (${#C_TEXT}), retrying..."
      TEXT="$C_TEXT"
    else
      echo "⚠️ Subagent failed to return output (attempt $retry)"
    fi
  done
fi

# 禁止硬截断：如果仍超长，直接跳过本轮
if [[ ${#TEXT} -gt 140 ]]; then
  echo "❌ Condense failed to get <=140 chars, skip this round (no hard truncate)"
  exit 75
fi

echo "Final text (${#TEXT} chars): $TEXT"

# 5) Post tweet via Playwright
POST=$(python3 "$WORKDIR/scripts/PostTweet_PW.py" --cookie-file "$COOKIE_FILE" --text "$TEXT" --media "$MEDIA")
echo "$POST"
if [[ $(echo "$POST" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))') != "True" ]]; then
  echo "❌ Tweet posting failed"
  exit 1
fi

# 6) Mark sent
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

# 7) Report to Discord
openclaw message send --channel discord --target channel:1476191544808837192 --message "✅ 脚本：rebang_home_hot_image_tweet_pw.sh
URL: $URL
媒体：$MEDIA
正文预览：${TEXT:0:120}
字符数：${#TEXT}" >/dev/null 2>&1 || true

echo "=== Done ==="
