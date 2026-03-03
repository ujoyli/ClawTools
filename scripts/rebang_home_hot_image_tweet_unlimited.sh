#!/usr/bin/env bash
set -euo pipefail

# Post a rebang.today hot item to X with:
# - non-repeating hook (rotating templates)
# - dedupe (skip items posted in last 24h)
# - image strategy: prefer original page image (og:image/twitter:image/first <img>), fallback to generated poster
# - always include source URL

ENV_FILE="/root/.config/x-twitter/.env"
WORKDIR="/root/.openclaw/workspace"
VENV_ACT="$WORKDIR/tmp_tiktokdownloader/.venv/bin/activate"
CACHE_JSON="$WORKDIR/data/rebang_posted.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export WORKDIR

cd "$WORKDIR"
# shellcheck disable=SC1090
source "$VENV_ACT"

# Pick an item list, then select an unposted one.
python3 - <<'PY' > /tmp/rebang_pick.json
import os, json, time, hashlib, re, subprocess

cache_path='/root/.openclaw/workspace/data/rebang_posted.json'
now=int(time.time())
window=24*3600
CDP_PORT=44407

# Load cache
cache={}
try:
    cache=json.load(open(cache_path,'r',encoding='utf-8'))
except Exception:
    cache={}
posted=cache.get('posted',{}) if isinstance(cache,dict) else {}

# Use puppeteer via CDP directly
node_script = """
const puppeteer = require('puppeteer-core');
(async () => {
  const browser = await puppeteer.connect({browserURL: 'http://localhost:""" + str(CDP_PORT) + """'});
  const pages = await browser.pages();
  const page = pages.length > 0 ? pages[0] : await browser.newPage();
  
  await page.goto('https://rebang.today/', {waitUntil: 'networkidle2', timeout: 60000});
  await new Promise(r => setTimeout(r, 5000));
  
  const items = await page.evaluate(() => {
    return Array.from(document.querySelectorAll('a'))
      .map(a => ({href: a.href, text: (a.textContent||'').trim().replace(/\\s+/g,' ')}))
      .filter(x => x.text.length > 15 && (x.href.includes('rebang.today/go') || x.href.includes('zhibo8.cc') || x.href.includes('zhihu.com') || x.href.includes('weibo.com') || x.href.includes('link.zhihu.com') || x.href.includes('douyin.com')));
  });
  
  console.log(JSON.stringify(items));
  await browser.disconnect();
})();
"""

env = os.environ.copy()
env['NODE_PATH'] = '/tmp/node_modules'
result = subprocess.run(['node', '-e', node_script], capture_output=True, text=True, env=env, timeout=90)
items = json.loads(result.stdout.strip()) if result.stdout.strip() else []

items=[i for i in items if isinstance(i,dict) and i.get('href') and i.get('text')]

def key_for(it):
    u=it.get('href','').strip()
    t=re.sub(r'\s+',' ',(it.get('text','') or '').strip())
    raw=(u+'|'+t).encode('utf-8','ignore')
    return hashlib.sha1(raw).hexdigest()

picked=None
for it in items:
    k=key_for(it)
    ts=posted.get(k,0) if isinstance(posted,dict) else 0
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

# Check pick result
PICK_RESULT=$(cat /tmp/rebang_pick.json)
OK=$(python3 -c "import json; print('1' if json.loads('$PICK_RESULT').get('ok') else '0')" || echo "0")

if [[ "$OK" != "1" ]]; then
  echo "Pick failed: $PICK_RESULT" >&2
  exit 1
fi

# Add sys import at top of Python block
python3 - <<'PY' > /tmp/rebang_parsed.json
import json
import sys
import re
import subprocess
pick=json.load(open('/tmp/rebang_pick.json','r',encoding='utf-8'))
title=pick.get('title','')
url=pick.get('url','')
key=pick.get('key','')
# Force Chinese translation if mostly non-English
if not re.search(r"[\u4e00-\u9fff]", title):  # No Chinese chars found -> translate
    try:
        prompt=f"把下面这句标题翻成自然口语中文（<= 40字），不要解释：\n{title}"
        out=subprocess.check_output(['openclaw','agent','--session-id','x-hotpost-zh','--thinking','minimal','--timeout','60','--json','--message',prompt], stderr=subprocess.DEVNULL, timeout=80)
        obj=json.loads(out.decode('utf-8','ignore'))
        trans=(obj.get('result',{}).get('payloads',[{}])[0].get('text') or '').strip()
        if trans:
            title=trans
    except Exception:
        pass
json.dump({'title':title, 'url':url, 'key':key}, sys.stdout, ensure_ascii=False)
PY

# Read back from file
TITLE=$(python3 -c "import json; print(json.load(open('/tmp/rebang_parsed.json','r',encoding='utf-8'))['title'])")
URL=$(python3 -c "import json; print(json.load(open('/tmp/rebang_parsed.json','r',encoding='utf-8'))['url'])")
KEY=$(python3 -c "import json; print(json.load(open('/tmp/rebang_parsed.json','r',encoding='utf-8')).get('key',''))")
export TITLE URL KEY WORKDIR

# 必应搜图 + 下载
IMG_PATH=$(python3 <<'PY'
import os, sys, json, subprocess, httpx, re

title = os.environ['TITLE']
workdir = os.environ['WORKDIR']
cdp_port = 44407

keywords = re.sub(r'[？！。，、""''《》\s]+', ' ', title).strip()
keywords = ' '.join(keywords.split()[:4])
if len(keywords) < 4:
    keywords = title[:20]

print(f"必应搜图：{keywords}", file=sys.stderr)

node_script = f"""
const puppeteer = require('puppeteer-core');
(async()=>{{
  const browser = await puppeteer.connect({{browserURL:'http://localhost:{cdp_port}'}});
  const page = await browser.newPage();
  const q = encodeURIComponent({json.dumps(keywords)});
  await page.goto('https://www.bing.com/images/search?q='+q+'&first=1', {{waitUntil:'networkidle2', timeout:30000}});
  await new Promise(r=>setTimeout(r,2000));

  const imgs = await page.evaluate(()=>{{
    return Array.from(document.querySelectorAll('a.iusc')).slice(0,5).map(a=>{{
      try {{
        const m = JSON.parse(a.getAttribute('m') || '{{}}');
        return m.murl || null;
      }} catch(e) {{ return null; }}
    }}).filter(x=>x);
  }});

  console.log(JSON.stringify(imgs));
  await page.close();
  await browser.disconnect();
}})();
"""

try:
    env = os.environ.copy()
    env['NODE_PATH'] = '/tmp/node_modules'
    result = subprocess.run(['node', '-e', node_script], capture_output=True, text=True, env=env, timeout=45)
    urls = json.loads(result.stdout.strip()) if result.stdout.strip() else []
    
    if urls:
        img_url = urls[0]
        print(f"找到图片：{img_url[:80]}", file=sys.stderr)
        ext = img_url.split('.')[-1].split('?')[0]
        if len(ext)>4 or ext.lower() not in ['jpg','jpeg','png','webp']: ext='jpg'
        img_path = f"{workdir}/tmp/rebang_image.{ext}"
        with httpx.Client(follow_redirects=True, headers={'User-Agent':'Mozilla/5.0'}) as client:
            r = client.get(img_url, timeout=15)
            r.raise_for_status()
            with open(img_path, 'wb') as f: f.write(r.content)
        print(img_path)
    else:
        print("无搜索结果，生成文字海报", file=sys.stderr)
        subprocess.run(['python3', f'{workdir}/scripts/douyin_hot_poster.py', title, f'{workdir}/tmp/rebang_image.png'], check=True)
        print(f"{workdir}/tmp/rebang_image.png")
except Exception as e:
    print(f"搜图失败：{e}，生成文字海报", file=sys.stderr)
    subprocess.run(['python3', f'{workdir}/scripts/douyin_hot_poster.py', title, f'{workdir}/tmp/rebang_image.png'], check=True)
    print(f"{workdir}/tmp/rebang_image.png")
PY
)

# Generate tweet text via agent
TEXT=$(python3 - <<'PY'
import os, subprocess, json

title = os.environ['TITLE'].strip()
url = os.environ['URL'].strip()

prompt = f"""你是 X (Twitter) 运营专家。根据以下热点标题写一条推文：

标题：{title}
来源链接：{url}

要求：
- ≤20 字！极短！像朋友随口一句吐槽
- 要有反差感/意外感/讽刺感
- 禁止 AI 套话（"一针见血"、"本质是"、"建议"等）
- 根据内容生成 1-2 个相关 #标签（别用 #今日热榜 这种泛标签）
- 不要链接（链接单独发）
- 像真人刷手机时随口说的，不是写文章

输出格式：只返回推文正文，不要引号，不要解释。
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
            # 文案（可能带标签）+ 原标题 + 链接
            text = f"{text}\n\n{title}\n\n{url}"
            print(text[:280])
        else:
            # Fallback
            print(f"{title}\n\n{url}")
    else:
        print(f"{title}\n\n{url}")
except Exception as e:
    print(f"{title}\n\n{url}")
PY
)

export NODE_PATH=/tmp/node_modules
# Post using simple CDP image poster
node /root/.openclaw/workspace/tmp/post_image_tweet.js "$TEXT" "$IMG_PATH" 44407

# After posting, record newest status URL from profile (best-effort)
node - <<'NODE'
const puppeteer = require('puppeteer-core');
(async()=>{
  const browser=await puppeteer.connect({browserURL:'http://localhost:18802'});
  const page=await browser.newPage();
  const profile='https://x.com/dashuai38953711';
  await page.goto(profile,{waitUntil:'networkidle2',timeout:45000});
  await new Promise(r=>setTimeout(r,6000));
  const newest=await page.evaluate(()=>{
    const arts=[...document.querySelectorAll('main section article')];
    for(const art of arts){
      const a=[...art.querySelectorAll('a')].map(x=>x.href).find(h=>h && /\/status\/(\d+)/.test(h));
      if(a) return a.split('?')[0];
    }
    return '';
  });
  console.log('NEWEST_STATUS='+newest);
  await browser.disconnect();
})();
NODE
