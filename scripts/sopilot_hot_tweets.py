#!/usr/bin/env python3
"""
Scrape sopilot.net/zh/hot-tweets via Playwright, save hot targets.
"""
import json, re, sys, os, time, argparse
from typing import List, Dict

REPLIED_PATH = "/root/.openclaw/workspace/data/x_replied_targets.json"
DEDUP_WINDOW = 72 * 3600
OUT_PATH = "/root/.openclaw/workspace/data/sopilot_hot_targets.json"


def parse_view_count(s: str) -> int:
    s = (s or "").replace(",", "").strip()
    m = re.match(r"([\d.]+)\s*万", s)
    if m:
        return int(float(m.group(1)) * 10000)
    m = re.match(r"([\d.]+)\s*[kK]", s)
    if m:
        return int(float(m.group(1)) * 1000)
    try:
        return int(float(s))
    except Exception:
        return 0


def get_replied_ids() -> set:
    try:
        obj = json.load(open(REPLIED_PATH, "r", encoding="utf-8"))
        replied = obj.get("replied", {})
        now = int(time.time())
        return {k for k, v in replied.items() if isinstance(v, int) and now - v < DEDUP_WINDOW}
    except Exception:
        return set()


def _extract_with_playwright() -> Dict:
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        b = p.chromium.launch(
            headless=True,
            executable_path='/usr/bin/chromium',
            args=['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu']
        )
        page = b.new_page(viewport={'width': 1366, 'height': 900})
        page.goto('https://sopilot.net/zh/hot-tweets', wait_until='domcontentloaded', timeout=90000)
        page.wait_for_timeout(10000)

        data = page.evaluate('''() => {
          const text = (document.querySelector('main')?.innerText || document.body?.innerText || '').trim();
          const ids = [...new Set(
            [...document.querySelectorAll('a[href*="tweetId="]')]
              .map(a => {
                const m = (a.href || '').match(/tweetId=(\d+)/);
                return m ? m[1] : null;
              })
              .filter(Boolean)
          )];
          return { text, ids, title: document.title || '' };
        }''')

        b.close()
        return data


def _parse_blocks(main_text: str, ids: List[str]) -> List[Dict]:
    # Split by follower marker which is stable on SoPilot cards, e.g. "2.2万粉"
    chunks = re.split(r'(?=(?:\d+(?:\.\d+)?(?:万)?粉))', main_text)

    results = []
    id_idx = 0
    seen_tid = set()

    for c in chunks:
        c = c.strip()
        if not c:
            continue

        hm = re.search(r'@(\w+)', c)
        if not hm:
            continue
        handle = hm.group(1)

        # name: text between followers and @handle
        nm = re.search(r'(?:\d+(?:\.\d+)?(?:万)?粉)\s*\n(.+?)\n@', c, re.S)
        name = (nm.group(1).strip() if nm else handle)

        # publish text block usually after "发布"
        tm = re.search(r'发布\s*\n\n([\s\S]*?)(?:\n\s*起爆概率|\n\s*预测浏览量|\n\s*预计可获得|$)', c)
        tweet_text = (tm.group(1).strip() if tm else "")
        tweet_text = re.sub(r'\n{3,}', '\n\n', tweet_text)[:500]

        pm = re.search(r'起爆概率\s*\n\s*(\d+)\s*%', c)
        prob = int(pm.group(1)) if pm else 0

        # age parse: e.g. "4小时前发布" / "35分钟前发布"
        age_h = 999.0
        ah = re.search(r'(\d+(?:\.\d+)?)\s*小时前发布', c)
        am = re.search(r'(\d+(?:\.\d+)?)\s*分钟前发布', c)
        if ah:
            age_h = float(ah.group(1))
        elif am:
            age_h = float(am.group(1)) / 60.0

        vm = re.search(r'预测浏览量\s*\n\s*([\d.,]+[万kK]?)', c)
        predicted = vm.group(1).strip() if vm else '0'

        em = re.search(r'预计可获得\s*([\d.,]+[万kK]?)\s*次曝光', c)
        exposure = em.group(1).strip() if em else '0'

        fm = re.search(r'(\d+(?:\.\d+)?(?:万)?粉)', c)
        followers = fm.group(1) if fm else '0'

        tid = ids[id_idx] if id_idx < len(ids) else None
        id_idx += 1

        if tid and tid in seen_tid:
            continue
        if tid:
            seen_tid.add(tid)

        url = f"https://x.com/{handle}/status/{tid}" if tid else ""

        # Basic quality gate
        if len(re.sub(r'\s+', '', tweet_text)) < 12:
            continue

        results.append({
            'handle': handle,
            'name': name,
            'followers': followers,
            'tweetText': tweet_text,
            'prob': prob,
            'predictedViews': predicted,
            'exposure': exposure,
            'age_h': round(age_h, 3),
            'tweetId': tid,
            'url': url,
        })

    return results


def scrape() -> List[Dict]:
    try:
        data = _extract_with_playwright()
        main_text = data.get('text', '')
        ids = data.get('ids', [])
        if not main_text or not ids:
            return []

        rows = _parse_blocks(main_text, ids)
        return rows
    except Exception as e:
        print(f"scrape error: {e}", file=sys.stderr)
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument("--min-views", type=int, default=10000)
    parser.add_argument("--min-prob", type=int, default=50)
    args = parser.parse_args()

    tweets = scrape()
    if not tweets:
        print("No tweets found", file=sys.stderr)
        sys.exit(1)

    print(f"Scraped {len(tweets)} tweets from sopilot")
    replied_ids = get_replied_ids()

    filtered = []
    for t in tweets:
        if t.get("prob", 0) < args.min_prob:
            continue
        pv = parse_view_count(t.get("predictedViews", "0"))
        if pv < args.min_views:
            continue
        if not t.get("url"):
            continue
        tid = t.get("tweetId", "")
        if tid in replied_ids:
            continue
        t["predictedViewsNum"] = pv
        filtered.append(t)

    filtered.sort(key=lambda x: x.get("predictedViewsNum", 0), reverse=True)
    top = filtered[:args.top]

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump({"updated_at": int(time.time()), "targets": top}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    for i, t in enumerate(top):
        print(f"{i+1}. @{t['handle']} 起爆{t.get('prob',0)}% 预测{t.get('predictedViews','0')} | {t.get('url','')}")
        print(f"   {t.get('tweetText','')[:100]}")

    print(f"\nSaved {len(top)} targets to {OUT_PATH}")


if __name__ == "__main__":
    main()
