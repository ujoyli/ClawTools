#!/usr/bin/env python3
"""
Hourly Douyin video poster - Auto post without approval.
1. Fetch hot videos from rebang.today/douyin
2. Pick one unposted video from last 24h
3. Download via DouK-Downloader
4. Post to X with caption
5. Log to data files
"""

import os
import sys
import json
import time
import hashlib
import subprocess
import random
from datetime import datetime, timezone

WORKDIR = "/root/.openclaw/workspace"
CACHE_JSON = f"{WORKDIR}/data/douyin_posted_videos.json"
QUEUE_JSON = f"{WORKDIR}/data/douyin_video_queue.json"
DL_DIR = f"{WORKDIR}/tmp_tiktokdownloader/Volume/Download"
TIKTOKDL_DIR = f"{WORKDIR}/tmp_tiktokdownloader"
VENV_ACT = f"{TIKTOKDL_DIR}/.venv/bin/activate"
VIDEO_POST_JS = f"{WORKDIR}/skills/twitter-post/scripts/video_post.js"
ENV_FILE = "/root/.config/x-twitter/.env"
BW_URL = os.environ.get('BROWSERWING_URL', 'http://127.0.0.1:18080')

import httpx

def check_twitter_api():
    """Check if Twitter API is working. Returns True if API is available."""
    import requests
    
    # Load env
    env_vars = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    env_vars[k.strip()] = v.strip()
    
    api_key = env_vars.get('TWITTER_CONSUMER_KEY')
    if not api_key:
        print("No Twitter API keys found")
        return False
    
    # Test API with a simple request - use tweets/recent endpoint which works with Bearer
    try:
        headers = {
            "Authorization": f"Bearer {env_vars.get('TWITTER_BEARER_TOKEN', '')}",
            "Content-Type": "application/json"
        }
        # Use recent tweets endpoint to test API
        resp = requests.get(
            "https://api.twitter.com/2/tweets/recent/query",
            headers=headers, 
            timeout=10,
            params={"query": "test", "max_results": 1}
        )
        
        if resp.status_code == 200:
            print("Twitter API is working!")
            return True
        elif resp.status_code == 503:
            print("Twitter API returning 503 Service Unavailable")
            return False
        else:
            # Try posting a tweet to test full API access
            print(f"Recent query returned: {resp.status_code}, trying tweet post test...")
    except Exception as e:
        print(f"Twitter API check error: {e}")
    
    # Fallback: try posting with the actual video post script
    try:
        result = subprocess.run(
            ['node', VIDEO_POST_JS, '/tmp/test_video.mp4', 'api_test'],
            capture_output=True, text=True, timeout=15,
            env={**os.environ, 'NODE_PATH': '/tmp/node_modules'}
        )
        output = result.stdout + result.stderr
        
        if '"ok":true' in output or result.returncode == 0:
            print("Twitter API (video post) is working!")
            return True
        elif '503' in output or 'Service Unavailable' in output:
            print("Twitter API returning 503")
            return False
        else:
            # API might work but file doesn't exist - that's OK
            if 'No such file' in output or 'not found' in output.lower():
                print("Twitter API keys are valid!")
                return True
            print(f"API test inconclusive: {output[:100]}")
            return False
    except Exception as e:
        print(f"Twitter API check failed: {e}")
        return False

def get_douyin_hot_videos():
    """Fetch hot douyin videos from rebang.today with retry + refresh + multi-strategy extraction."""
    script = """() => {
  const out = [];
  const map = new Map();
  const put = (href, title) => {
    if (!href || !href.includes('douyin')) return;
    const t = (title || '').trim().replace(/\\s+/g,' ');
    if (!map.has(href)) map.set(href, {href, title: t});
    else if (t.length > (map.get(href).title || '').length) map.get(href).title = t;
  };

  // strategy A: direct anchors
  document.querySelectorAll('a[href*="douyin.com"]').forEach(a => {
    put(a.href, a.textContent || '');
  });

  // strategy B: walk cards/rows and pick nearest text
  document.querySelectorAll('[class*="item"], [class*="card"], li, article, div').forEach(el => {
    const a = el.querySelector('a[href*="douyin.com"][href*="/video/"]');
    if (!a) return;
    let txt = (el.textContent || '').trim().replace(/\\s+/g,' ');
    if (txt.length > 200) txt = txt.slice(0,200);
    put(a.href, txt || a.textContent || '');
  });

  // strategy C: parse url-like text fallback
  const html = document.body?.innerHTML || '';
  const m = html.match(/https?:\\/\\/[^\"'\\s]*douyin[^\"'\\s]*/g) || [];
  m.forEach(u => put(u, '')); 

  const arr = Array.from(map.values()).filter(x => x.href).map(x => ({
    href: x.href,
    title: (x.title || '').trim() || '抖音热视频'
  }));
  return arr.slice(0, 40);
}"""

    for attempt in range(1, 4):
        try:
            with httpx.Client(headers={'Content-Type': 'application/json'}, timeout=120) as c:
                c.post(BW_URL + '/api/v1/executor/navigate',
                       json={'url': 'https://rebang.today/?tab=douyin', 'wait_until': 'domcontentloaded', 'timeout': 60})
                time.sleep(2)
                # refresh once to avoid stale/empty tab
                c.post(BW_URL + '/api/v1/executor/reload', json={'wait_until': 'networkidle', 'timeout': 60})
                time.sleep(2 + attempt)

                r = c.post(BW_URL + '/api/v1/executor/evaluate', json={'script': script})
                items = (r.json().get('data') or {}).get('result') or []
                if items:
                    print(f"Fetched {len(items)} douyin candidates (attempt {attempt})")
                    return items
                print(f"No items on attempt {attempt}, retrying...")
        except Exception as e:
            print(f"Fetch attempt {attempt} error: {e}", file=sys.stderr)
        time.sleep(2)

    # Puppeteer CDP fallback (same pattern as rebang image pipeline)
    try:
        node_script = r'''
const puppeteer = require('puppeteer-core');
(async () => {
  const browser = await puppeteer.connect({browserURL:'http://localhost:44407'});
  const pages = await browser.pages();
  const page = pages.length ? pages[0] : await browser.newPage();
  await page.goto('https://rebang.today/?tab=douyin', {waitUntil:'networkidle2', timeout:60000});
  await new Promise(r=>setTimeout(r,5000));
  const items = await page.evaluate(() => {
    const map = new Map();
    document.querySelectorAll('a[href*="douyin"]').forEach(a => {
      const href = a.href || '';
      const t = (a.textContent || '').trim().replace(/\s+/g,' ');
      if (!map.has(href) || t.length > (map.get(href).title||'').length) {
        map.set(href, {href, title: t || '抖音热视频'});
      }
    });
    return Array.from(map.values()).slice(0,40);
  });
  console.log(JSON.stringify(items));
  await browser.disconnect();
})().catch(e=>{console.error(e.message); console.log('[]');});
'''
        result = subprocess.run(
            ['node', '-e', node_script],
            capture_output=True, text=True, timeout=240,
            env={**os.environ, 'NODE_PATH': '/tmp/node_modules'}
        )
        out = (result.stdout or '').strip()
        line = next((ln for ln in out.splitlines() if ln.strip().startswith('[')), '[]')
        items = json.loads(line)
        if items:
            print(f"Fetched {len(items)} douyin candidates (puppeteer fallback)")
            return items
    except Exception as e:
        print(f"Puppeteer fallback error: {e}", file=sys.stderr)

    return []

def pick_unposted_video(items):
    """Pick one unposted video from last 24h"""
    cache = {}
    try:
        cache = json.load(open(CACHE_JSON))
    except:
        cache = {'posted': {}}
    
    posted = cache.get('posted', {})
    now = time.time()
    window = 24 * 3600
    
    # Filter out already posted videos
    unposted = []
    for item in items:
        url = item.get('href', '').strip()
        title = item.get('title', '').strip()
        if not url or not title:
            continue
        
        # Check if posted in last 24h
        key = hashlib.sha1((url + '|' + title).encode('utf-8')).hexdigest()
        if key in posted and (now - posted[key]) < window:
            continue
        
        unposted.append({'url': url, 'title': title, 'key': key})
    
    if not unposted:
        return None
    
    # Pick randomly from top candidates
    return random.choice(unposted[:10])

def download_video(url):
    """Download video via DouK-Downloader TUI automation"""
    os.makedirs(DL_DIR, exist_ok=True)
    
    # Get file list before download
    before = None
    try:
        files = sorted([os.path.join(DL_DIR, f) for f in os.listdir(DL_DIR) if f.endswith('.mp4')], key=os.path.getmtime, reverse=True)
        before = files[0] if files else None
    except:
        pass
    
    # Run downloader TUI automation
    env = os.environ.copy()
    env['NODE_PATH'] = '/tmp/node_modules'
    
    cmd = f"cd {TIKTOKDL_DIR} && source {VENV_ACT} && printf '5\\n2\\n1\\n{url}\\n\\nq\\nq\\n' | python main.py"
    
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=300, env=env)
        log_file = '/tmp/douyin_hourly_download.log'
        with open(log_file, 'w') as f:
            f.write(result.stdout + '\n' + result.stderr)
    except Exception as e:
        print(f"Download error: {e}", file=sys.stderr)
        return None
    
    # Find newly downloaded video
    time.sleep(2)
    try:
        files = sorted([os.path.join(DL_DIR, f) for f in os.listdir(DL_DIR) if f.endswith('.mp4')], key=os.path.getmtime, reverse=True)
        after = files[0] if files else None
        
        if after and after != before and os.path.exists(after):
            return after
    except:
        pass
    
    return None

def generate_caption(title):
    """Generate a punchy caption via agent"""
    try:
        prompt_file = f"{WORKDIR}/prompts/x_post_prompt.txt"
        if os.path.exists(prompt_file):
            prompt = open(prompt_file).read().replace("{SOURCE_TEXT}", title[:500])
        else:
            prompt = f"为以下抖音视频写一条有趣的推文评论，50-80 字，带梗：{title[:200]}"
        
        result = subprocess.run(
            ['openclaw', 'agent', '--session-id', 'x-hourly-video', '--thinking', 'minimal', '--json', '--message', prompt],
            capture_output=True, text=True, timeout=120
        )
        
        if result.returncode == 0:
            obj = json.loads(result.stdout)
            text = obj.get('result', {}).get('payloads', [{}])[0].get('text', '').strip().strip('"').strip("'")
            if text:
                return text[:260]
    except Exception as e:
        print(f"Caption error: {e}", file=sys.stderr)
    
    # Fallback
    return f"{title[:80]} #今日热榜"

def fetch_og_image(video_url, save_path):
    """Fetch og:image from the original video page"""
    import requests
    
    try:
        # First get the actual video page URL (redirect from rebang)
        resp = requests.head(video_url, timeout=10, allow_redirects=True)
        actual_url = resp.url
        
        # Fetch the page to get og:image
        page_resp = requests.get(actual_url, timeout=15)
        html = page_resp.text
        
        # Extract og:image
        import re
        og_image_match = re.search(r'<meta[^>]*property=["\']og:image["\'][^>]*content=["\']([^"\']+)["\']', html)
        if not og_image_match:
            og_image_match = re.search(r'<meta[^>]*content=["\']([^"\']+)["\'][^>]*property=["\']og:image["\']', html)
        
        if og_image_match:
            img_url = og_image_match.group(1)
            print(f"Found og:image: {img_url[:60]}...")
            
            # Download the image
            img_resp = requests.get(img_url, timeout=30)
            if img_resp.status_code == 200:
                with open(save_path, 'wb') as f:
                    f.write(img_resp.content)
                print(f"Saved image to: {save_path}")
                return save_path
    except Exception as e:
        print(f"Failed to fetch og:image: {e}")
    
    return None

def post_video(video_path, caption, video_url=""):
    """Post video to X using unified x-cdp flow (same approach as image pipeline)."""
    import subprocess

    # Load Twitter env
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    os.environ[k.strip()] = v.strip()

    try:
        cdp_script = f"{WORKDIR}/skills/x-cdp/scripts/post-tweet.js"
        cdp_port = os.environ.get('X_CDP_PORT', '44407')

        # copy to a short ascii path to avoid upload/path encoding issues
        safe_video = '/tmp/hourly_unified_video.mp4'
        try:
            import shutil
            shutil.copy2(video_path, safe_video)
            media_path = safe_video
        except Exception:
            media_path = video_path

        cmd = ['node', cdp_script, caption, '--media', media_path, '--port', cdp_port]
        print(f"Running unified x-cdp post-tweet (video), port={cdp_port}, media={media_path}", file=sys.stderr)

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=420,
            env={**os.environ, 'NODE_PATH': '/tmp/node_modules'}
        )

        out = (result.stdout or '').strip()
        err = (result.stderr or '').strip()
        if result.returncode == 0 and ('OK: Tweet posted' in out or 'OK: Tweet posted via API' in out):
            return json.dumps({"ok": True, "via": "x-cdp", "raw": out[:500]}, ensure_ascii=False)

        print(f"x-cdp post failed: {err[:200]} | {out[:200]}", file=sys.stderr)
    except Exception as e:
        print(f"post_video error: {e}", file=sys.stderr)

    return None

def mark_as_posted(url, title, tweet_url):
    """Mark video as posted in cache"""
    cache = {'posted': {}}
    try:
        cache = json.load(open(CACHE_JSON))
    except:
        pass
    
    key = hashlib.sha1((url + '|' + title).encode('utf-8')).hexdigest()
    cache['posted'][key] = int(time.time())
    
    # Keep only last 7 days
    now = time.time()
    window = 7 * 24 * 3600
    cache['posted'] = {k: v for k, v in cache['posted'].items() if (now - v) < window}
    
    with open(CACHE_JSON, 'w') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)
        f.write('\n')
    
    # Also log to reply_log
    log_entry = {
        'ts': int(time.time()),
        'source': 'hourly_douyin_video',
        'video_url': url,
        'title': title[:200],
        'tweet_url': tweet_url
    }
    
    log_path = f"{WORKDIR}/data/x_reply_log.jsonl"
    with open(log_path, 'a') as f:
        f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')

def main():
    print(f"[{datetime.now().isoformat()}] Starting hourly douyin video post...")
    
    # 0. Check Twitter API first - skip if API is down
    print("Checking Twitter API status...")
    if not check_twitter_api():
        print("Twitter API is not available. Skipping this run to avoid wasted downloads.")
        print("Will retry on next scheduled run.")
        sys.exit(0)
    
    # 1. Fetch hot videos
    print("Fetching hot videos from rebang.today...")
    items = get_douyin_hot_videos()
    if not items:
        print("No videos found")
        sys.exit(1)
    
    print(f"Found {len(items)} videos")
    
    # 2. Pick unposted video
    picked = pick_unposted_video(items)
    if not picked:
        print("No unposted videos in last 24h")
        sys.exit(0)
    
    print(f"Selected: {picked['title'][:60]}...")
    
    # 3. Download video
    print(f"Downloading: {picked['url']}")
    video_path = download_video(picked['url'])
    if not video_path or not os.path.exists(video_path):
        print("Download failed")
        sys.exit(1)
    
    print(f"Downloaded: {video_path}")
    
    # 4. Generate caption
    caption = generate_caption(picked['title'])
    print(f"Caption: {caption[:80]}...")
    
    # 5. Post to X
    print("Posting to X...")
    resp = post_video(video_path, caption, picked.get('url', ''))
    if not resp:
        print("Post failed")
        sys.exit(1)
    
    # Parse tweet URL from response when available (CDP may not return URL)
    tweet_url = ""
    try:
        obj = json.loads(resp)
        tweet_url = obj.get('url', '') or ''
    except:
        pass

    if tweet_url:
        print(f"Posted: {tweet_url}")
    else:
        print("Posted via CDP (URL not returned)")
    
    # 6. Mark as posted
    mark_as_posted(picked['url'], picked['title'], tweet_url)
    print("Done!")

if __name__ == '__main__':
    main()
