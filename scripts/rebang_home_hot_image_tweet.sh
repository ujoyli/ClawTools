#!/usr/bin/env bash
set -euo pipefail

# Post a rebang.today hot item to X with:
# - non-repeating hook (rotating templates)
# - dedupe (skip items posted in last 24h)
# - image strategy: prefer original page image (og:image/twitter:image/first <img>), fallback to generated poster
# - always include source URL

ENV_FILE="/root/.config/x-twitter/.env"
WORKDIR="/root/.openclaw/workspace"
VENV_ACT="$WORKDIR/tmp_tiktokdownloader/.venv/bin/activate"  # has pillow + httpx
CACHE_JSON="$WORKDIR/data/rebang_posted.json"

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

# Pick an item list, then select an unposted one.
python - <<'PY' > /tmp/rebang_pick.json
import os, json, time, hashlib, re
import httpx

BW=os.environ.get('BROWSERWING_URL','http://127.0.0.1:18080')
cache_path='/root/.openclaw/workspace/data/rebang_posted.json'
now=int(time.time())
window=24*3600

# Load cache
cache={}
try:
    cache=json.load(open(cache_path,'r',encoding='utf-8'))
except Exception:
    cache={}
posted=cache.get('posted',{}) if isinstance(cache,dict) else {}

with httpx.Client(headers={'Content-Type':'application/json'}) as c:
    c.post(BW+'/api/v1/executor/navigate', json={'url':'https://rebang.today/','wait_until':'domcontentloaded','timeout':60}, timeout=120).raise_for_status()
    c.post(BW+'/api/v1/executor/wait', json={'identifier':'a[href]','state':'visible','timeout':20}, timeout=30).raise_for_status()
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
  return Array.from(map.values()).filter(x=>x.text && x.href).slice(0, 40);
}"""
    r=c.post(BW+'/api/v1/executor/evaluate', json={'script':script}, timeout=60)
    r.raise_for_status()
    obj=r.json()
    items=(obj.get('data') or {}).get('result') or []

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
    print(json.dumps({'ok':False,'error':'no items'}))
elif not picked:
    # All were posted recently; fall back to first
    picked=items[0]
    picked['_key']=key_for(picked)
    print(json.dumps({'ok':True,'dedupe':'exhausted','title':picked['text'][:180],'url':picked['href'],'key':picked['_key']}, ensure_ascii=False))
else:
    print(json.dumps({'ok':True,'dedupe':'ok','title':picked['text'][:180],'url':picked['href'],'key':picked['_key']}, ensure_ascii=False))
PY

OK=$(python - <<'PY'
import json
obj=json.loads(open('/tmp/rebang_pick.json','r',encoding='utf-8').read())
print('1' if obj.get('ok') else '0')
PY
)

if [[ "$OK" != "1" ]]; then
  cat /tmp/rebang_pick.json >&2
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
KEY=$(python - <<'PY'
import json
obj=json.loads(open('/tmp/rebang_pick.json','r',encoding='utf-8').read())
print(obj.get('key',''))
PY
)

export TITLE URL KEY

# 1) Try to fetch an original image from the target page
IMG_ORIG="$WORKDIR/tmp/rebang_orig.jpg"
IMG_POSTER="$WORKDIR/tmp/rebang_poster.png"
USE_IMG="$IMG_POSTER"
export IMG_ORIG

python - <<'PY' > /tmp/rebang_img_path.txt
import os, re, io, math
from urllib.parse import urljoin
import httpx

url=os.environ['URL'].strip()
out=os.environ['IMG_ORIG']

headers={
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36',
}

# Validate image to avoid 1x1 / solid-color placeholders.
def looks_ok(img_bytes: bytes) -> bool:
    if not img_bytes or len(img_bytes) < 15_000:
        return False
    try:
        from PIL import Image
        im = Image.open(io.BytesIO(img_bytes))
        im = im.convert('RGB')
        w,h = im.size
        if w < 500 or h < 280:
            return False
        # sample grayscale stddev
        import random
        samples=[]
        for _ in range(2500):
            x=random.randrange(w)
            y=random.randrange(h)
            r,g,b=im.getpixel((x,y))
            samples.append((r+g+b)/3)
        mean=sum(samples)/len(samples)
        var=sum((v-mean)**2 for v in samples)/len(samples)
        std=math.sqrt(var)
        return std >= 18.0
    except Exception:
        return False

c=httpx.Client(follow_redirects=True, headers=headers, timeout=20)
img_url=None
try:
    r=c.get(url)
    r.raise_for_status()
    html=r.text
    # prefer og:image / twitter:image
    for pat in [
        r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']',
        r'<meta[^>]+name=["\']twitter:image["\'][^>]+content=["\']([^"\']+)["\']',
    ]:
        m=re.search(pat, html, flags=re.I)
        if m:
            img_url=m.group(1).strip(); break
    if not img_url:
        # fallback: first <img>
        m=re.search(r'<img[^>]+src=["\']([^"\']+)["\']', html, flags=re.I)
        if m:
            img_url=m.group(1).strip()

    if img_url:
        img_url=urljoin(url, img_url)
        ir=c.get(img_url)
        ir.raise_for_status()
        if looks_ok(ir.content):
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out,'wb') as f:
                f.write(ir.content)
            os.chmod(out, 0o644)
            print(out)
        else:
            print('')
    else:
        print('')
except Exception:
    print('')
finally:
    c.close()
PY

if [[ -s /tmp/rebang_img_path.txt ]]; then
  # Got an original image
  USE_IMG="$IMG_ORIG"
else
  # Fallback: generate a simple poster
  python scripts/douyin_hot_poster.py "$TITLE" "$IMG_POSTER"
fi

# 2) Compose non-repeating hook + always include URL
TEXT=$(python - <<'PY'
import os, hashlib, datetime

title=os.environ['TITLE'].strip()
url=os.environ['URL'].strip()
key=os.environ.get('KEY','')

hooks=[
  '别刷了，这条可能会反转。',
  '这事儿我越看越不对劲。',
  '信息量不大，但后劲很大。',
  '先别站队，先看完。',
  '今天热榜里最“怪”的一条。',
  '你可能会忽略它，但它正在发酵。',
  '把它当段子就亏了。',
  '这条像预告片：后面还有。',
  '看完你再决定转不转。',
  '别被标题骗了，重点在细节。',
]

seed=(key or title)+datetime.datetime.now().strftime('%Y-%m-%d-%H')
i=int(hashlib.sha1(seed.encode('utf-8','ignore')).hexdigest(),16)%len(hooks)
hook=hooks[i]

# trim title for tweet
if len(title)>90:
  title=title[:90]+'…'

print(f"{hook}\n\n{title}\n\n来源：{url}\n#今日热榜")
PY
)

# 3) Post and update dedupe cache
RESP=$(node skills/twitter-post/scripts/image_post.js "$USE_IMG" "$TEXT")
echo "$RESP"

TWEET_URL=$(python3 - <<'PY' <<<"$RESP"
import json,sys
obj=json.loads(sys.stdin.read() or '{}')
print(obj.get('url') or '')
PY
)
export TWEET_URL

if [[ -n "$TWEET_URL" && -n "$KEY" ]]; then
  python3 - <<'PY'
import os, json, time
path='/root/.openclaw/workspace/data/rebang_posted.json'
key=os.environ.get('KEY','')
url=os.environ.get('URL','')
tweet_url=os.environ.get('TWEET_URL','')
now=int(time.time())
obj={}
try:
    obj=json.load(open(path,'r',encoding='utf-8'))
except Exception:
    obj={}
if not isinstance(obj,dict):
    obj={}
obj.setdefault('posted',{})
obj['posted'][key]=now
obj['last']={'key':key,'url':url,'tweet_url':tweet_url}
with open(path,'w',encoding='utf-8') as f:
    json.dump(obj,f,ensure_ascii=False,indent=2)
    f.write('\n')
PY
fi
