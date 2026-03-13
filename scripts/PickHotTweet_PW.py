#!/usr/bin/env python3
import argparse, json, re, sys, time
import importlib.util
from datetime import datetime, timezone
from zoneinfo import ZoneInfo


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


def chinese_char_count(s: str) -> int:
    return len(re.findall(r'[\u4e00-\u9fff]', s or ''))


def english_letter_count(s: str) -> int:
    return len(re.findall(r'[A-Za-z]', s or ''))


def is_english_tweet(s: str) -> bool:
    zh = chinese_char_count(s)
    en = english_letter_count(s)
    # Require substantial English and very little Chinese
    return en >= 12 and zh <= 2 and en > zh * 4


def is_chinese_tweet(s: str) -> bool:
    zh = chinese_char_count(s)
    en = english_letter_count(s)
    # Require substantial Chinese and Chinese-dominant text
    return zh >= 6 and zh >= en


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
    # Don't add expires field if not present - Playwright doesn't accept None
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cookie-file', required=True)
    ap.add_argument('--replied-file', default='/root/.openclaw/workspace/data/x_replied_targets.json')
    ap.add_argument('--max-age-min', type=int, default=120)  # 2 hours rule
    ap.add_argument('--min-views', type=int, default=10000)   # minimum views threshold
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

    # Load blacklist
    blacklist = []
    try:
        blacklist = [line.strip() for line in open('/root/.openclaw/workspace/data/blacklist.txt') if line.strip()]
    except:
        pass

    # Load topic filters using importlib (avoid sys.path manipulation)
    # Initialize defaults first to ensure variables always exist
    is_political = lambda txt: False
    get_topic_score = lambda txt: 0
    tech_keywords = []
    society_keywords = []
    
    try:
        spec = importlib.util.spec_from_file_location('x_topic_filters', '/root/.openclaw/workspace/data/x_topic_filters.py')
        if spec and spec.loader:
            x_topic_filters = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(x_topic_filters)
            is_political = getattr(x_topic_filters, 'is_political', is_political)
            get_topic_score = getattr(x_topic_filters, 'get_topic_score', get_topic_score)
            tech_keywords = [kw.lower() for kw in getattr(x_topic_filters, 'TECH_KEYWORDS', [])]
            society_keywords = [kw.lower() for kw in getattr(x_topic_filters, 'SOCIETY_KEYWORDS', [])]
    except Exception as e:
        print(f"[warn] Failed to load topic filters: {e}", file=sys.stderr)
        pass  # Keep defaults

    best = None

    # Time-based language rule (Asia/Shanghai):
    # 03:00-08:59 -> English only
    # other times -> Chinese only
    sh_hour = datetime.now(ZoneInfo('Asia/Shanghai')).hour
    english_only_window = 3 <= sh_hour < 9

    for t in tweets:
        if t['tid'] in replied:
            continue
        # Check blacklist
        url_lower = t.get('url', '').lower()
        if any(b in url_lower for b in blacklist):
            continue
        # Filter political content
        if is_political(t.get('text', '')):
            continue
        text = t.get('text', '')
        if len(re.findall(r'[\u4e00-\u9fffA-Za-z]', text)) < 8:
            continue

        # Apply time-window language rule
        if english_only_window:
            if not is_english_tweet(text):
                continue
        else:
            if not is_chinese_tweet(text):
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

        # Parse engagement metrics before filtering (supports both EN and CN)
        label = t.get('label', '')
        # Replies: "1292 回复" or "1292 repl"
        replies = parse_count(re.search(r'(\d+)\s*回复', label).group(1)) if re.search(r'(\d+)\s*回复', label) else (parse_count(re.search(r'(\d[\d\.,KMB]*)\s*repl', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s*repl', label, re.I) else 0)
        # Retweets: "497 次转帖" or "497 repost/retweet"
        retweets = parse_count(re.search(r'(\d+)\s*次转帖', label).group(1)) if re.search(r'(\d+)\s*次转帖', label) else (parse_count(re.search(r'(\d[\d\.,KMB]*)\s*(?:repost|retweet)', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s*(?:repost|retweet)', label, re.I) else 0)
        # Likes: "5023 喜欢" or "5023 like"
        likes = parse_count(re.search(r'(\d+)\s*喜欢', label).group(1)) if re.search(r'(\d+)\s*喜欢', label) else (parse_count(re.search(r'(\d[\d\.,KMB]*)\s*like', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s*like', label, re.I) else 0)
        # Views: "398918 次观看" or "398918 view"
        views = parse_count(re.search(r'(\d+)\s*次观看', label).group(1)) if re.search(r'(\d+)\s*次观看', label) else (parse_count(re.search(r'(\d[\d\.,KMB]*)\s*view', label, re.I).group(1)) if re.search(r'(\d[\d\.,KMB]*)\s*view', label, re.I) else 0)

        # New rule from 大帅: only reply to tweets <3h old AND >1000 views
        if views < args.min_views:
            continue

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
        # Topic boost: tech > society > others
        text_lower = t.get('text', '').lower()
        if any(kw in text_lower for kw in tech_keywords):
            score += 80
        elif any(kw in text_lower for kw in society_keywords):
            score += 40

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
