#!/usr/bin/env python3
import argparse, json, os, re
from urllib.parse import urljoin, urlparse
import requests
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
TMP_DIR = '/root/.openclaw/workspace/tmp'
os.makedirs(TMP_DIR, exist_ok=True)


def clean_text(s: str) -> str:
    return re.sub(r'\s+', ' ', (s or '')).strip()


def normalize_title(title: str) -> str:
    title = clean_text(title)
    title = re.sub(r'\s*-\s*[^-]*社区[\s\S]*$', '', title)
    title = re.sub(r'\s*-\s*[^-]*论坛[\s\S]*$', '', title)
    title = re.sub(r'\s*-\s*虎扑[\s\S]*$', '', title, flags=re.IGNORECASE)
    title = re.sub(r'虎扑社区', '', title, flags=re.IGNORECASE)
    title = re.sub(r'虎扑', '', title, flags=re.IGNORECASE)
    title = re.sub(r'\s*-\s*步行街.*$', '', title)
    return title.strip()


def find_content_root(soup: BeautifulSoup):
    root = soup.find('div', class_=re.compile(r'^post-content_main-post-info'))
    if root:
        d = root.find('div', class_='thread-content-detail')
        if d:
            return d
    return soup.find('div', class_='thread-content-detail')


def pick_media(detail, base_url):
    medias = []
    if not detail:
        return medias
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
    uniq, seen = [], set()
    for m in medias:
        if m['url'] in seen:
            continue
        seen.add(m['url'])
        uniq.append(m)
    return uniq


def extract_with_requests(url: str):
    resp = requests.get(url, headers={'User-Agent': UA}, timeout=45, verify=False)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, 'html.parser')
    title = normalize_title((soup.title.string if soup.title else ''))
    detail = find_content_root(soup)
    body = clean_text(detail.get_text(' ', strip=True)) if detail else ''
    medias = pick_media(detail, url) if detail else []
    return title, body, medias


def extract_with_playwright(url: str):
    with sync_playwright() as p:
        b = p.chromium.launch(
            headless=True,
            executable_path='/usr/bin/chromium',
            args=['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu']
        )
        ctx = b.new_context(user_agent=UA, viewport={'width': 1366, 'height': 900})
        page = ctx.new_page()
        page.goto(url, wait_until='domcontentloaded', timeout=70000)
        page.wait_for_timeout(2500)

        title = normalize_title(page.title() or '')

        payload = page.evaluate('''() => {
          const detail = document.querySelector('.post-content_main-post-info .thread-content-detail')
                       || document.querySelector('.thread-content-detail');
          if (!detail) return {body:'', media:[]};

          const body = (detail.innerText || '').replace(/\s+/g,' ').trim();
          const media = [];
          const seen = new Set();

          for (const img of detail.querySelectorAll('img')) {
            const src = img.getAttribute('src') || img.getAttribute('data-origin') || img.getAttribute('data-original') || img.getAttribute('data-src') || '';
            if (!src) continue;
            const abs = new URL(src, location.href).href;
            const low = abs.toLowerCase();
            if (/(avatar|logo|icon|def_|emoji|sprite)/.test(low)) continue;
            if (seen.has(abs)) continue;
            seen.add(abs);
            media.push({type:'image', url:abs});
          }

          for (const v of detail.querySelectorAll('video')) {
            const src = v.getAttribute('src') || (v.querySelector('source') ? v.querySelector('source').getAttribute('src') : '');
            if (!src) continue;
            const abs = new URL(src, location.href).href;
            if (seen.has(abs)) continue;
            seen.add(abs);
            media.push({type:'video', url:abs});
          }

          return {body, media};
        }''')

        b.close()
        return title, clean_text(payload.get('body', '')), payload.get('media', [])


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

    title = body = ''
    medias = []
    fallback_reason = ''

    try:
        title, body, medias = extract_with_requests(args.url)
    except Exception as e:
        fallback_reason = f'requests_failed: {e}'

    # requests often misses JS-rendered thread body; fallback to Playwright
    if not title or not body:
        try:
            p_title, p_body, p_medias = extract_with_playwright(args.url)
            title = title or p_title
            body = body or p_body
            medias = medias or p_medias
        except Exception as e:
            if not fallback_reason:
                fallback_reason = f'playwright_failed: {e}'

    if not title and not body and not medias:
        print(json.dumps({'ok': False, 'error': 'extract_failed', 'detail': fallback_reason}))
        return

    picked = medias[0] if medias else None
    saved = download_media(picked['url']) if picked and args.download else None

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
