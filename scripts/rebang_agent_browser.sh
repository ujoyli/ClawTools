#!/usr/bin/env bash
set -euo pipefail

# Rebang hot item poster using agent-browser
# - Pick item from rebang.today
# - Bing image search
# - Post to X with agent-browser

ENV_FILE="/root/.config/x-twitter/.env"
WORKDIR="/root/.openclaw/workspace"
CACHE_JSON="$WORKDIR/data/rebang_posted.json"
COOKIE_JSON="/root/x_cookies.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi

source "$ENV_FILE"
export WORKDIR

# Pick an item from rebang
echo "Picking rebang item..."
python3 - <<'PY' > /tmp/rebang_pick.json
import os, json, time, hashlib, re, subprocess

cache_path='/root/.openclaw/workspace/data/rebang_posted.json'
now=int(time.time())
window=24*3600

cache={}
try:
    cache=json.load(open(cache_path,'r',encoding='utf-8'))
except:
    cache={}
posted=cache.get('posted',{}) if isinstance(cache,dict) else {}

# Use agent-browser to fetch rebang
print("Fetching rebang.today with agent-browser...")
result = subprocess.run(
    ['agent-browser', 'open', 'https://rebang.today/', '--timeout', '60000'],
    capture_output=True, text=True, timeout=90
)
time.sleep(5)

# Get page HTML via get html on body
result = subprocess.run(
    ['agent-browser', 'get', 'html', 'body'],
    capture_output=True, text=True, timeout=60
)
html = result.stdout.strip() if result.stdout else ""

# Parse links from HTML
import re
items = []
for match in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*>([^<]+)</a>', html):
    href = match.group(1)
    text = match.group(2).strip()
    if len(text) > 15 and any(x in href for x in ['rebang.today/go', 'douyin.com', 'zhihu.com', 'weibo.com']):
        items.append({'href': href, 'text': text})

# Deduplicate
seen = set()
unique_items = []
for it in items:
    key = it['href'] + '|' + it['text'][:50]
    if key not in seen:
        seen.add(key)
        unique_items.append(it)

items = unique_items[:20]
print(f"Found {len(items)} items", file=os.sys.stderr)

def key_for(it):
    u=it.get('href','').strip()
    t=re.sub(r'\s+',' ',(it.get('text','') or '').strip())
    return hashlib.sha1((u+'|'+t).encode('utf-8','ignore')).hexdigest()

picked=None
for it in items:
    k=key_for(it)
    ts=posted.get(k,0)
    if not ts or now-ts>window:
        picked=it
        picked['_key']=k
        break

if not items:
    print(json.dumps({'ok':False,'error':'no items found'}))
elif not picked:
    picked=items[0]
    picked['_key']=key_for(picked)
    print(json.dumps({'ok':True,'dedupe':'exhausted','title':picked['text'][:180],'url':picked['href'],'key':picked['_key']}, ensure_ascii=False))
else:
    print(json.dumps({'ok':True,'dedupe':'ok','title':picked['text'][:180],'url':picked['href'],'key':picked['_key']}, ensure_ascii=False))
PY

PICK_RESULT=$(cat /tmp/rebang_pick.json)
OK=$(python3 -c "import json; print('1' if json.loads('$PICK_RESULT').get('ok') else '0')" 2>/dev/null || echo "0")

if [[ "$OK" != "1" ]]; then
  echo "Pick failed: $PICK_RESULT" >&2
  agent-browser close 2>/dev/null || true
  exit 1
fi

# Parse title and URL
TITLE=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d['title'])")
URL=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d['url'])")
KEY=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d.get('key',''))")

echo "Selected: $TITLE"

# Generate tweet text via agent
echo "Generating tweet text..."
TEXT=$(python3 - <<'PY'
import os, subprocess, json

title = os.environ['TITLE']
url = os.environ['URL']

prompt = f"""你是 X (Twitter) 运营专家。根据以下热点标题写一条推文：

标题：{title}
来源链接：{url}

要求：
- ≤20 字！极短！像朋友随口一句吐槽
- 要有反差感/意外感/讽刺感
- 禁止 AI 套话
- 根据内容生成 1-2 个相关 #标签
- 不要链接

输出格式：只返回推文正文。
"""

try:
    result = subprocess.run(
        ['openclaw', 'agent', '--session-id', 'x-rebang-tweet', '--thinking', 'minimal', '--json', '--message', prompt],
        capture_output=True, text=True, timeout=90
    )
    if result.returncode == 0:
        obj = json.loads(result.stdout)
        text = obj.get('result', {}).get('payloads', [{}])[0].get('text', '').strip().strip('"').strip("'")
        if text and len(text) > 3:
            text = f"{text}\n\n{title}\n\n{url}"
            print(text[:280])
        else:
            print(f"{title}\n\n{url}")
    else:
        print(f"{title}\n\n{url}")
except Exception as e:
    print(f"{title}\n\n{url}")
PY
)

export TEXT

# Bing image search
echo "Searching for image..."
IMG_PATH="$WORKDIR/tmp/rebang_image.jpg"
python3 - <<'PY'
import os, sys, json, subprocess, httpx, re

title = os.environ['TITLE']
workdir = os.environ['WORKDIR']

keywords = re.sub(r'[？！。，、""''《》\s]+', ' ', title).strip()
keywords = ' '.join(keywords.split()[:4])
if len(keywords) < 4:
    keywords = title[:20]

print(f"Bing search: {keywords}", file=sys.stderr)

# Use agent-browser for image search
subprocess.run(['agent-browser', 'open', f'https://www.bing.com/images/search?q={keywords}'], 
               capture_output=True, timeout=60)
subprocess.run(['agent-browser', 'wait', '--load', 'networkidle'], 
               capture_output=True, timeout=30)
time.sleep(3)

# Get image URLs via eval
js_script = """() => {
  return Array.from(document.querySelectorAll('img')).map(img => img.src).filter(s => s && s.includes('th.bing.com')).slice(0, 5);
}"""
result = subprocess.run(['agent-browser', 'eval', js_script], 
                       capture_output=True, text=True, timeout=60)
try:
    output = result.stdout.strip()
    if '✓' in output:
        json_str = output.split('✓', 1)[1].strip()
        img_urls = json.loads(json_str)
    else:
        img_urls = json.loads(output) if output else []
    img_url = img_urls[0] if img_urls else None
except:
    img_url = None

if img_url:
    print(f"Found image: {img_url[:80]}", file=sys.stderr)
    # Download
    ext = 'jpg'
    img_path = f"{workdir}/tmp/rebang_image.{ext}"
    try:
        with httpx.Client(follow_redirects=True, headers={'User-Agent':'Mozilla/5.0'}) as client:
            r = client.get(img_url, timeout=15)
            r.raise_for_status()
            with open(img_path, 'wb') as f: f.write(r.content)
        print(img_path)
    except Exception as e:
        print(f"Download failed: {e}", file=sys.stderr)
        sys.exit(1)
else:
    print("No image found, generating poster", file=sys.stderr)
    subprocess.run(['python3', f'{workdir}/scripts/douyin_hot_poster.py', title, f'{workdir}/tmp/rebang_image.png'], check=True)
    print(f"{workdir}/tmp/rebang_image.png")
PY

echo "Image ready: $IMG_PATH"

# Post to X using agent-browser
echo "Posting to X..."

# Open X and inject cookies
agent-browser open "https://x.com/home"
sleep 3

# Inject cookies from JSON file
python3 - <<'PY'
import json, subprocess

cookies = json.load(open('/root/x_cookies.json', 'r'))
for c in cookies:
    name = c['name']
    value = c['value']
    domain = c.get('domain', '.x.com')
    path = c.get('path', '/')
    subprocess.run(['agent-browser', 'cookies', 'set', name, value, 
                    '--domain', domain, '--path', path], 
                   capture_output=True)
print("Cookies injected")
PY

# Navigate to compose
agent-browser open "https://x.com/compose/post"
agent-browser wait --load networkidle
sleep 3

# Type text
echo "Typing tweet..."
agent-browser fill '[data-testid="tweetTextarea_0_label"]' "$TEXT"
sleep 2

# Upload image
echo "Uploading image..."
agent-browser upload 'input[type="file"][data-testid="fileInput"]' "$IMG_PATH"
sleep 5

# Click tweet button
echo "Clicking tweet button..."
agent-browser click '[data-testid="tweetButton"]'
sleep 5

echo "Tweet posted!"

# Mark as posted
python3 - <<'PY'
import json, time, hashlib

cache = {'posted': {}}
try:
    cache = json.load(open('/root/.openclaw/workspace/data/rebang_posted.json','r',encoding='utf-8'))
except:
    pass

key = os.environ.get('KEY', '')
if key:
    cache['posted'][key] = int(time.time())
    # Keep only last 7 days
    now = time.time()
    cache['posted'] = {k: v for k, v in cache['posted'].items() if (now - v) < 7*24*3600}
    
    with open('/root/.openclaw/workspace/data/rebang_posted.json', 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print("Marked as posted")
PY

agent-browser close
echo "Done!"
