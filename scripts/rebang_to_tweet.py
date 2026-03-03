#!/usr/bin/env python3
"""
Unified News -> Tweet poster (NO shell variables, pure Python + Node).
- Fetch hot items from a pool of sources (via BrowserWing)
- Deep-crawl target URL for original image (og:image)
- Auto-translate English titles to Chinese
- Generate poster image as fallback
- Post to X via CDP
- Log to data files
"""

import os
import sys
import json
import time
import hashlib
import re
import subprocess
import httpx
import random
from datetime import datetime

WORKDIR = "/root/.openclaw/workspace"
CACHE_JSON = f"{WORKDIR}/data/rebang_posted.json"
IMG_POSTER = f"{WORKDIR}/tmp/rebang_poster.png"
ENV_FILE = "/root/.config/x-twitter/.env"
BW_URL = os.environ.get('BROWSERWING_URL', 'http://127.0.0.1:18080')
CDP_PORT = 18802
NODE_PATH = '/tmp/node_modules'

SOURCES = [
    {"url": "https://rebang.today/?tab=top", "parser": "rebang"},
]

def load_env():
    if not os.path.exists(ENV_FILE): return
    with open(ENV_FILE) as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                os.environ[k.strip()] = v.strip()

def get_rebang_items(c, url):
    """Fetch hot items from rebang.today list"""
    try:
        c.post(BW_URL + '/api/v1/executor/navigate',
               json={'url': url, 'wait_until': 'domcontentloaded', 'timeout': 60})
        time.sleep(3)
        script = """() => {
          return Array.from(document.querySelectorAll('a'))
            .map(a => ({href: a.href, text: (a.textContent||'').trim().replace(/\\s+/g,' ')}))
            .filter(x => {
                const t = x.text.toLowerCase();
                const isSport = t.includes('中超') || t.includes('英超') || t.includes('cba') || t.includes('nba') || t.includes('绝杀') || t.includes('逆转') || t.includes('胜场') || t.includes('篮') || t.includes('足') || t.includes('赛');
                return x.text.length > 15 && !isSport && (x.href.includes('rebang.today/go') || x.href.includes('zhihu.com') || x.href.includes('weibo.com') || x.href.includes('link.zhihu.com') || x.href.includes('douyin.com'));
            });
        }"""
        r = c.post(BW_URL + '/api/v1/executor/evaluate', json={'script': script})
        items = (r.json().get('data') or {}).get('result') or []
        if items:
            return items

        # Fallback: parse plain text blocks when site doesn't expose <a href>
        r2 = c.post(BW_URL + '/api/v1/executor/evaluate', json={'script': "() => (document.body && document.body.innerText) || ''"})
        text = ((r2.json().get('data') or {}).get('result') or '').strip()
        if not text:
            return []

        lines = [x.strip() for x in text.splitlines() if x.strip()]
        out = []
        for i, line in enumerate(lines[:-1]):
            if re.fullmatch(r'\d{1,3}', line):
                title = lines[i + 1].strip()
                if len(title) < 12:
                    continue
                low = title.lower()
                if any(k in low for k in ['中超', '英超', 'cba', 'nba', '绝杀', '逆转', '胜场', '篮', '足', '赛']) and len(title) < 40:
                    continue
                out.append({'href': url, 'text': title})
                if len(out) >= 30:
                    break
        return out
    except Exception as e:
        print(f"List parser error: {e}", file=sys.stderr)
        return []

def get_original_image_via_search(title):
    """Use Bing image search via CDP browser to find a relevant news image"""
    # Extract short keywords from title (first 15 chars or key phrase)
    keywords = re.sub(r'[？！。，、""''《》\s]+', ' ', title).strip()
    # Take first meaningful chunk
    keywords = ' '.join(keywords.split()[:4])
    if len(keywords) < 4:
        keywords = title[:20]

    print(f"Searching Bing images for: {keywords}")

    node_script = f"""
const puppeteer = require('puppeteer-core');
(async()=>{{
  const browser = await puppeteer.connect({{browserURL:'http://localhost:{CDP_PORT}'}});
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
        env['NODE_PATH'] = NODE_PATH
        result = subprocess.run(['node', '-e', node_script], capture_output=True, text=True, env=env, timeout=45)
        urls = json.loads(result.stdout.strip()) if result.stdout.strip() else []
        if urls:
            # Pick first valid image URL
            print(f"Found {len(urls)} search images, using first: {urls[0][:80]}")
            return urls[0]
        print("No search images found")
        return None
    except Exception as e:
        print(f"Image search error: {e}", file=sys.stderr)
        return None

def download_image(url):
    if not url or not url.startswith('http'): return None
    try:
        ext = url.split('.')[-1].split('?')[0]
        if len(ext)>4 or ext.lower() not in ['jpg','jpeg','png','webp']: ext='jpg'
        path = f"{WORKDIR}/tmp/rebang_orig.{ext}"
        with httpx.Client(follow_redirects=True, headers={'User-Agent': 'Mozilla/5.0'}) as client:
            r = client.get(url)
            r.raise_for_status()
            with open(path, 'wb') as f: f.write(r.content)
        return path
    except: return None

def pick_unposted(items):
    cache = {}
    try: cache = json.load(open(CACHE_JSON))
    except: cache = {}
    posted = cache.get('posted', {}) if isinstance(cache, dict) else {}
    now = int(time.time())

    def key_for(it):
        u, t = it.get('href', '').strip(), re.sub(r'\s+', ' ', it.get('text', '').strip())
        return hashlib.sha1((u + '|' + t).encode('utf-8')).hexdigest()

    # 1. Filter out already posted items (last 24h)
    unposted = []
    for item in items:
        k = key_for(item)
        if not posted.get(k) or now - posted[k] > 24*3600:
            item['_key'] = k
            unposted.append(item)

    # 2. Randomly pick from the top unposted items (e.g., top 10)
    if unposted:
        # Limit to top 15 hot items to keep it relevant, then shuffle
        pool = unposted[:15]
        return random.choice(pool)

    return items[0] if items else None

def humanize_text(title):
    """Use agent to write a human-like tweet based on the news title"""
    try:
        prompt = open(f"{WORKDIR}/prompts/x_post_prompt.txt").read().replace("{SOURCE_TEXT}", title[:500])
        out = subprocess.check_output(['openclaw', 'agent', '--session-id', 'x-hotpost-human', '--thinking', 'minimal', '--json', '--message', prompt], text=True)
        text = json.loads(out).get('result', {}).get('payloads', [{}])[0].get('text', '').strip()
        text = text.strip('"').strip("'")
        return text if text else title
    except: return title

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args_cli = parser.parse_args()
    load_env()

    with httpx.Client(headers={'Content-Type': 'application/json'}, timeout=120) as c:
        source = random.choice(SOURCES)
        items = get_rebang_items(c, source['url'])
        if not items: sys.exit(1)

        picked = pick_unposted(items)
        if not picked: sys.exit(0)

        title, url = picked['text'], picked['href']

        # 1. Humanize content (Reduce AI taste)
        tweet_body = humanize_text(title)

        # 2. Fetch real image via Bing image search (using news keywords)
        # Extract clean title for search
        clean_title = picked.get('text', '').split('？')[0].split('，')[0][:30]
        orig_img_url = get_original_image_via_search(clean_title)
        image_path = download_image(orig_img_url)

        # 3. Fallback to poster ONLY if no image found at all
        if not image_path:
            # We already have humanized text, no need to re-translate for poster
            subprocess.run([sys.executable, f"{WORKDIR}/scripts/douyin_hot_poster.py", tweet_body, IMG_POSTER], check=False)
            image_path = IMG_POSTER if os.path.exists(IMG_POSTER) else None

        tweet_text = f"{tweet_body}\n\n来源：{url}\n#今日热榜"

        if args_cli.dry_run:
            subprocess.run(['openclaw', 'message', 'send', '--channel', 'discord', '--target', 'channel:1476191544808837192', '--message', f"【热榜推送审核】\n{tweet_text}"], check=False)
            if image_path: subprocess.run(['openclaw', 'message', 'send', '--channel', 'discord', '--target', 'channel:1476191544808837192', '--media', image_path], check=False)
            print("Draft sent to Discord.")
            sys.exit(0)

if __name__ == '__main__':
    main()
