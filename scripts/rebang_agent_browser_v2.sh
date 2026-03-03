#!/usr/bin/env bash
set -euo pipefail

# Rebang hot item poster using CDP browser + agent-browser for X posting
# 1. Pick item from rebang (via puppeteer CDP)
# 2. Bing image search (via agent-browser)
# 3. Post to X (via agent-browser with cookie injection)

WORKDIR="/root/.openclaw/workspace"
CACHE_JSON="$WORKDIR/data/rebang_posted.json"
COOKIE_JSON="/root/x_cookies.json"
CDP_PORT=44407

export WORKDIR

# Ensure Chromium is running
echo "Starting Chromium..."
bash "$WORKDIR/tmp/start_chromium.sh" > /dev/null 2>&1 || true
sleep 2

# Pick an item from rebang via puppeteer
echo "Picking rebang item..."
python3 - <<'PY' > /tmp/rebang_pick.json
import os, json, time, hashlib, re, subprocess

cache_path = '/root/.openclaw/workspace/data/rebang_posted.json'
now = int(time.time())
window = 24 * 3600
CDP_PORT = 44407

cache = {}
try:
    cache = json.load(open(cache_path, 'r', encoding='utf-8'))
except:
    cache = {}
posted = cache.get('posted', {}) if isinstance(cache, dict) else {}

# Use puppeteer via CDP
node_script = f"""
const puppeteer = require('puppeteer-core');
(async () => {{
  try {{
    const browser = await puppeteer.connect({{browserURL: 'http://localhost:{CDP_PORT}'}});
    const pages = await browser.pages();
    const page = pages.length > 0 ? pages[0] : await browser.newPage();
    
    await page.goto('https://rebang.today/', {{waitUntil: 'networkidle2', timeout: 60000}});
    await new Promise(r => setTimeout(r, 8000));
    
    const items = await page.evaluate(() => {{
      return Array.from(document.querySelectorAll('a'))
        .map(a => ({{href: a.href, text: (a.textContent||'').trim().replace(/\\s+/g,' ')} }))
        .filter(x => x.text.length > 15 && (x.href.includes('rebang.today/go') || x.href.includes('douyin.com') || x.href.includes('zhihu.com') || x.href.includes('weibo.com')));
    }});
    
    console.log(JSON.stringify(items.slice(0, 20)));
    await browser.disconnect();
  }} catch (e) {{
    console.log('[]');
  }}
}})();
"""

env = os.environ.copy()
env['NODE_PATH'] = '/tmp/node_modules'
result = subprocess.run(['node', '-e', node_script], capture_output=True, text=True, env=env, timeout=90)
items = json.loads(result.stdout.strip()) if result.stdout.strip() else []

def key_for(it):
    u = it.get('href', '').strip()
    t = re.sub(r'\s+', ' ', (it.get('text', '') or '').strip())
    return hashlib.sha1((u + '|' + t).encode('utf-8', 'ignore')).hexdigest()

picked = None
for it in items:
    k = key_for(it)
    ts = posted.get(k, 0)
    if not ts or now - ts > window:
        picked = it
        picked['_key'] = k
        break

if not items:
    print(json.dumps({'ok': False, 'error': 'no items found'}))
elif not picked:
    picked = items[0]
    picked['_key'] = key_for(picked)
    print(json.dumps({'ok': True, 'dedupe': 'exhausted', 'title': picked['text'][:180], 'url': picked['href'], 'key': picked['_key']}, ensure_ascii=False))
else:
    print(json.dumps({'ok': True, 'dedupe': 'ok', 'title': picked['text'][:180], 'url': picked['href'], 'key': picked['_key']}, ensure_ascii=False))
PY

PICK_RESULT=$(cat /tmp/rebang_pick.json)
OK=$(python3 -c "import json; print('1' if json.loads('$PICK_RESULT').get('ok') else '0')" 2>/dev/null || echo "0")

if [[ "$OK" != "1" ]]; then
  echo "Pick failed: $PICK_RESULT" >&2
  exit 1
fi

TITLE=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d['title'])")
URL=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d['url'])")
KEY=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d.get('key',''))")

echo "Selected: $TITLE"

# Generate tweet text via agent
echo "Generating tweet text..."
TEXT=$(python3 - <<'PY'
import os, subprocess, json

title = os.environ.get('TITLE', '')
url = os.environ.get('URL', '')

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

# Bing image search via agent-browser
echo "Searching for image..."
IMG_PATH="$WORKDIR/tmp/rebang_image.jpg"

# Extract keywords
KEYWORDS=$(echo "$TITLE" | python3 -c "import sys,re; t=sys.stdin.read(); k=re.sub(r'[？！。，、\"\"''《》\s]+',' ',t).strip(); print(' '.join(k.split()[:4]) if len(k.split())>=4 else t[:20])")

agent-browser open "https://www.bing.com/images/search?q=$KEYWORDS"
agent-browser wait --load networkidle
sleep 3

# Get first image URL via eval
IMG_URL=$(agent-browser eval "() => document.querySelector('img.mimg')?.src" 2>&1 | grep -v "✓" | head -1 || echo "")

if [[ -n "$IMG_URL" && "$IMG_URL" == http* ]]; then
    echo "Found image: $IMG_URL"
    python3 -c "
import httpx
url = '$IMG_URL'
try:
    with httpx.Client(follow_redirects=True, headers={'User-Agent':'Mozilla/5.0'}) as c:
        r = c.get(url, timeout=15)
        with open('$IMG_PATH', 'wb') as f: f.write(r.content)
    print('Downloaded')
except Exception as e:
    print(f'Failed: {e}')
    exit(1)
"
else
    echo "No image found, generating poster"
    python3 "$WORKDIR/scripts/douyin_hot_poster.py" "$TITLE" "$WORKDIR/tmp/rebang_image.png"
    IMG_PATH="$WORKDIR/tmp/rebang_image.png"
fi

echo "Image ready: $IMG_PATH"

# Post to X using agent-browser
echo "Posting to X..."

# Open X
agent-browser open "https://x.com/home"
sleep 5

# Inject cookies
echo "Injecting cookies..."
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
                   capture_output=True, timeout=30)
print("Cookies injected")
PY

# Navigate to compose
agent-browser open "https://x.com/compose/post"
agent-browser wait --load networkidle
sleep 5

# Type text
echo "Typing tweet..."
agent-browser fill '[data-testid="tweetTextarea_0_label"]' "$TEXT"
sleep 2

# Upload image
echo "Uploading image..."
agent-browser upload 'input[type="file"][data-testid="fileInput"]' "$IMG_PATH"
sleep 8

# Click tweet button
echo "Clicking tweet button..."
agent-browser click '[data-testid="tweetButton"]'
sleep 5

echo "Tweet posted!"

# Mark as posted
python3 - <<'PY'
import json, time, hashlib, os

cache = {'posted': {}}
try:
    cache = json.load(open('/root/.openclaw/workspace/data/rebang_posted.json','r',encoding='utf-8'))
except:
    pass

key = os.environ.get('KEY', '')
if key:
    cache['posted'][key] = int(time.time())
    now = time.time()
    cache['posted'] = {k: v for k, v in cache['posted'].items() if (now - v) < 7*24*3600}
    
    with open('/root/.openclaw/workspace/data/rebang_posted.json', 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print("Marked as posted")
PY

agent-browser close
echo "Done!"
