#!/usr/bin/env python3
import argparse, json, os, re
from urllib.parse import urljoin, urlparse
import requests
from bs4 import BeautifulSoup

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
TMP_DIR = '/root/.openclaw/workspace/tmp'
os.makedirs(TMP_DIR, exist_ok=True)


def clean_text(s: str) -> str:
    return re.sub(r'\s+', ' ', (s or '')).strip()


def find_content_root(soup: BeautifulSoup):
    # class startswith post-content_main-post-info
    root = soup.find('div', class_=re.compile(r'^post-content_main-post-info'))
    if root:
        d = root.find('div', class_='thread-content-detail')
        if d:
            return d
    # fallback
    return soup.find('div', class_='thread-content-detail')


def pick_media(detail, base_url):
    medias = []
    if not detail:
        return medias
    # images
    for img in detail.find_all('img'):
        src = img.get('src') or img.get('data-origin') or img.get('data-original') or img.get('data-src')
        if not src:
            continue
        src = urljoin(base_url, src)
        if not src.startswith('http'):
            continue
        low = src.lower()
        if any(x in low for x in ['avatar', 'logo', 'icon', 'def_', 'emoji', 'sprite']):
            continue
        medias.append({'type': 'image', 'url': src})
    # videos
    for v in detail.find_all('video'):
        src = v.get('src')
        if not src:
            s = v.find('source')
            src = s.get('src') if s else None
        if not src:
            continue
        src = urljoin(base_url, src)
        if src.startswith('http'):
            medias.append({'type': 'video', 'url': src})
    # unique
    uniq = []
    seen = set()
    for m in medias:
        if m['url'] in seen:
            continue
        seen.add(m['url'])
        uniq.append(m)
    return uniq


def download_media(media_url: str):
    try:
        r = requests.get(media_url, headers={'User-Agent': UA, 'Referer': 'https://bbs.hupu.com/'}, timeout=45, verify=False)
        r.raise_for_status()
        if len(r.content) < 2048:
            return None
        name = os.path.basename(urlparse(media_url).path) or f'media_{os.getpid()}'
        name = re.sub(r'[^A-Za-z0-9._-]', '_', name)
        if '.' not in name:
            name += '.bin'
        path = os.path.join(TMP_DIR, name)
        if os.path.exists(path):
            base, ext = os.path.splitext(path)
            path = f"{base}_{os.getpid()}{ext}"
        with open(path, 'wb') as f:
            f.write(r.content)
        return path
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('url')
    ap.add_argument('--download', action='store_true', default=True)
    args = ap.parse_args()

    try:
        resp = requests.get(args.url, headers={'User-Agent': UA}, timeout=45, verify=False)
        resp.raise_for_status()
    except Exception as e:
        print(json.dumps({'ok': False, 'error': f'fetch_failed: {e}'}))
        return

    soup = BeautifulSoup(resp.text, 'html.parser')
    title = clean_text((soup.title.string if soup.title else '').replace('- 虎扑社区', ''))
    detail = find_content_root(soup)
    if not detail:
        print(json.dumps({'ok': False, 'error': 'thread-content-detail not found', 'title': title}))
        return

    body = clean_text(detail.get_text(' ', strip=True))
    medias = pick_media(detail, args.url)

    saved = None
    picked = medias[0] if medias else None
    if picked and args.download:
        saved = download_media(picked['url'])

    out = {
        'ok': True,
        'title': title,
        'body': body,
        'media': medias,
        'picked_media': picked,
        'saved_media': saved,
    }
    print(json.dumps(out, ensure_ascii=False))


if __name__ == '__main__':
    requests.packages.urllib3.disable_warnings()
    main()
