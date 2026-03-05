#!/usr/bin/env python3
import argparse, json, re, time
from datetime import datetime, timezone


def parse_count(s: str) -> int:
    if not s:
        return 0
    s = s.strip().upper().replace(',', '')
    m = re.search(r'([0-9]+(?:\.[0-9]+)?)([KMB]?)', s)
    if not m:
        return 0
    v = float(m.group(1))
    u = m.group(2)
    if u == 'K':
        v *= 1_000
    elif u == 'M':
        v *= 1_000_000
    elif u == 'B':
        v *= 1_000_000_000
    return int(v)


def to_playwright_cookie(c):
    same_site = str(c.get('sameSite', '')).lower()
    if same_site in ('no_restriction', 'none'):
        ss = 'None'
    elif same_site == 'strict':
        ss = 'Strict'
    else:
        ss = 'Lax'
    d = {
        'name': c['name'],
        'value': c['value'],
        'domain': c['domain'],
        'path': c.get('path', '/'),
        'httpOnly': bool(c.get('httpOnly', False)),
        'secure': bool(c.get('secure', True)),
        'sameSite': ss,
    }
    if c.get('expirationDate'):
        d['expires'] = int(c['expirationDate'])
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cookie-file', required=True)
    ap.add_argument('--replied-file', default='/root/.openclaw/workspace/data/x_replied_targets.json')
    ap.add_argument('--max-age-min', type=int, default=240)
    args = ap.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        print(json.dumps({'ok': False, 'error': 'playwright not installed'}))
        return

    cookies_raw = json.load(open(args.cookie_file, 'r', encoding='utf-8'))
    cookies = [to_playwright_cookie(c) for c in cookies_raw if c.get('name') and c.get('value') and c.get('domain')]

    replied = {}
    now = int(time.time())
    try:
        replied = json.load(open(args.replied_file, 'r', encoding='utf-8')).get('replied', {})
        replied = {k: v for k, v in replied.items() if isinstance(v, int) and now - v < 72 * 3600}
    except Exception:
        replied = {}

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox', '--disable-dev-shm-usage'])
        context = browser.new_context(viewport={'width': 1366, 'height': 900})
        context.add_cookies(cookies)
        page = context.new_page()

        try:
            page.goto('https://x.com/home', wait_until='domcontentloaded', timeout=60000)
        except Exception:
            page.goto('https://twitter.com/home', wait_until='domcontentloaded', timeout=60000)
        page.wait_for_timeout(7000)

        tweets = page.evaluate("""
() => {
  const rows = [...document.querySelectorAll('article[data-testid="tweet"]')].slice(0, 60).map(a => {
    const text = (a.querySelector('[data-testid="tweetText"]')?.textContent || '').trim();
    const time = a.querySelector('time')?.getAttribute('datetime') || '';
    const link = [...a.querySelectorAll('a[href*="/status/"]')].find(l => l.querySelector('time'));
    const url = link ? link.href : '';
    const m = url.match(/status\/(\d+)/);
    const tid = m ? m[1] : '';

    const group = a.querySelector('[role="group"]');
    const label = group ? (group.getAttribute('aria-label') || '') : '';
    const hasMedia = !!a.querySelector('[data-testid="tweetPhoto"], video, [data-testid="card.wrapper"]');
    const hasQuestion = /\?|？/.test(text);
    const controversy = /(hot take|unpopular|离谱|崩了|骗局|错了|假|垃圾|scam|fake)/i.test(text);
    const hasExternalLink = [...a.querySelectorAll('a[href]')].some(x => {
      const h = x.getAttribute('href') || '';
      return /^https?:\/\//.test(h) && !/x\.com|twitter\.com/.test(h);
    });
    const isReply = /^replying to/i.test((a.innerText || '').trim());

    return { text, time, url, tid, label, hasMedia, hasQuestion, controversy, hasExternalLink, isReply };
  }).filter(t => t.url && t.tid && t.text.length >= 10);
  return rows;
}
""")
        browser.close()

    best = None
    for t in tweets:
        if t['tid'] in replied:
            continue
        if len(re.findall(r'[\u4e00-\u9fffA-Za-z]', t['text'])) < 8:
            continue

        age_min = 60
        if t.get('time'):
            try:
                dt = datetime.fromisoformat(t['time'].replace('Z', '+00:00'))
                age_min = max(1, (datetime.now(timezone.utc) - dt).total_seconds() / 60)
            except Exception:
                pass
        if age_min > args.max_age_min:
            continue

        label = t.get('label', '')
        replies = parse_count(re.search(r'(\d[\d\.,KMB]*)\s+repl', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s+repl', label, re.I) else 0
        retweets = parse_count(re.search(r'(\d[\d\.,KMB]*)\s+repost|retweet', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s+repost|retweet', label, re.I) else 0
        likes = parse_count(re.search(r'(\d[\d\.,KMB]*)\s+like', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s+like', label, re.I) else 0
        views = parse_count(re.search(r'(\d[\d\.,KMB]*)\s+view', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s+view', label, re.I) else 0

        velocity = (views + 1) / age_min
        score = replies * 8 + retweets * 5 + likes * 2 + velocity
        if t['hasMedia']:
            score += 60
        if t['hasQuestion']:
            score += 40
        if t['controversy']:
            score += 30
        if t['hasExternalLink']:
            score -= 35
        if t['isReply']:
            score -= 20

        t.update({'score': round(score, 2), 'ageMin': round(age_min, 1), 'views': views, 'likes': likes, 'rt': retweets, 'replies': replies})
        if best is None or t['score'] > best['score']:
            best = t

    if not best:
        print(json.dumps({'ok': False, 'error': 'no suitable viral targets'}))
        return

    replied[best['tid']] = now
    json.dump({'replied': replied}, open(args.replied_file, 'w', encoding='utf-8'), ensure_ascii=False)
    with open(args.replied_file, 'a', encoding='utf-8') as f:
        f.write('\n')

    best['ok'] = True
    print(json.dumps(best, ensure_ascii=False))


if __name__ == '__main__':
    main()
