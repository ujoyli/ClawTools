#!/usr/bin/env python3
import os
import re
import json
import time
import shutil
import random
import subprocess
from pathlib import Path
from urllib.parse import urljoin

import urllib.request

WORKSPACE = Path('/root/.openclaw/workspace')
STATE_DIR = WORKSPACE / '.openclaw' / 'tophub-douyin'
STATE_FILE = STATE_DIR / 'state.json'
LOG_FILE = STATE_DIR / 'run.log'
TMP_DIR = STATE_DIR / 'tmp'

TOPHUB_HOME = 'https://tophub.today'
TARGET_LABEL = '抖音总榜'

YTDLP = '/root/.local/bin/yt-dlp'
VIDEO_POST_JS = '/root/.openclaw/workspace/skills/twitter-post/scripts/video_post.js'

MAX_TRIES = 10
MAX_USED_KEEP = 500

HASHTAGS = ['#抖音', '#热榜', '#热点']


def log(msg: str):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    ts = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())
    with LOG_FILE.open('a', encoding='utf-8') as f:
        f.write(f'[{ts}] {msg}\n')


def load_state():
    if not STATE_FILE.exists():
        return {"used": []}
    try:
        return json.loads(STATE_FILE.read_text(encoding='utf-8'))
    except Exception:
        return {"used": []}


def save_state(st):
    st['used'] = st.get('used', [])[-MAX_USED_KEEP:]
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding='utf-8')


def fetch(url: str, timeout=20) -> str:
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode('utf-8', errors='ignore')


def find_douyin_board_url(html: str) -> str:
    # robust-ish: scan <a ...>...</a>, strip inner tags, match label
    for m in re.finditer(r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>', html, flags=re.I | re.S):
        href = m.group(1)
        inner = m.group(2)
        text = re.sub(r'<[^>]+>', '', inner)
        text = re.sub(r'\s+', ' ', text).strip()
        if TARGET_LABEL in text:
            return urljoin(TOPHUB_HOME, href)
    return ''


def parse_board_items(html: str):
    # extract links near list items; tophub board pages typically include /n/<id>
    # We'll collect (title, href) pairs.
    items = []
    # Prefer structured "item" blocks: title in <a ...>Title</a>
    for m in re.finditer(r'<a[^>]+href="([^"]+)"[^>]*>([^<]{2,120})</a>', html):
        href = m.group(1)
        title = re.sub(r'\s+', ' ', m.group(2)).strip()
        if not title or title == TARGET_LABEL:
            continue
        # ignore nav
        if title in ('首页', '日报', '动态'):
            continue
        # keep only entries that look like hot items: tophub board pages usually have /n/xxxx
        if '/n/' not in href and 'douyin.com' not in href and 'iesdouyin.com' not in href:
            continue
        items.append((title, urljoin(TOPHUB_HOME, href)))

    # de-dup
    seen = set()
    out = []
    for t,u in items:
        if u in seen:
            continue
        seen.add(u)
        out.append((t,u))
    return out


def resolve_final_video_url(tophub_item_url: str) -> str:
    # Some tophub items redirect; we can just give yt-dlp the tophub link directly.
    return tophub_item_url


def run(cmd, timeout=300):
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def download_video(url: str, out_dir: Path) -> Path | None:
    out_dir.mkdir(parents=True, exist_ok=True)
    template = str(out_dir / 'video.%(ext)s')
    cmd = [YTDLP, '-f', 'bv*+ba/b', '--merge-output-format', 'mp4', '-o', template, url]
    code, out, err = run(cmd, timeout=600)
    if code != 0:
        log(f'yt-dlp failed code={code} err={err[:300]}')
        return None

    # find resulting mp4
    for p in out_dir.iterdir():
        if p.suffix.lower() in ('.mp4', '.mkv', '.webm'):
            return p
    return None


def craft_tweet(title: str) -> str:
    hooks = [
        '这条我真没绷住…',
        '热榜第一到底凭什么？',
        '这也能上热榜？结果看完我服了。',
        '今天的爆点来了：',
        '别划走，后面这一下太狠了：',
    ]
    hook = random.choice(hooks)
    tags = ' '.join(random.sample(HASHTAGS, k=min(3, len(HASHTAGS))))

    # keep short; video carries the info
    text = f"{hook}\n{title}\n\n{tags}"
    # hard cap for safety
    return text[:260]


def post_video(video_path: Path, text: str):
    cmd = ['node', VIDEO_POST_JS, str(video_path), text]
    code, out, err = run(cmd, timeout=600)
    if code != 0:
        return False, out or err
    return True, out


def main():
    if not Path(YTDLP).exists():
        log('yt-dlp missing')
        return 1

    st = load_state()
    used = set(st.get('used', []))

    home = fetch(TOPHUB_HOME)
    board_url = find_douyin_board_url(home)
    if not board_url:
        log('failed to find douyin board url')
        return 1

    board_html = fetch(board_url)
    items = parse_board_items(board_html)
    if not items:
        log('no items parsed')
        return 1

    TMP_DIR.mkdir(parents=True, exist_ok=True)

    tried = 0
    for title, item_url in items:
        if tried >= MAX_TRIES:
            break
        tried += 1

        if item_url in used:
            continue

        url = resolve_final_video_url(item_url)
        # Clean temp
        if TMP_DIR.exists():
            shutil.rmtree(TMP_DIR)
        TMP_DIR.mkdir(parents=True, exist_ok=True)

        log(f'trying: {title} ({url})')
        video = download_video(url, TMP_DIR)
        if not video:
            continue

        # size guard (512MB)
        size = video.stat().st_size
        if size > 450 * 1024 * 1024:
            log(f'skip too large: {size}')
            continue

        tweet = craft_tweet(title)
        ok, resp = post_video(video, tweet)
        if ok:
            used.add(item_url)
            st['used'] = list(used)
            save_state(st)
            log(f'posted ok: {resp}')
            print(resp)
            return 0
        else:
            log(f'post failed: {resp[:300]}')

    log('no post succeeded')
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
