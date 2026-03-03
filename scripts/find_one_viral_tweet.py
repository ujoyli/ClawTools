import asyncio
import os
import json
import time
import random
import subprocess
from urllib.parse import quote

CDP_PORT = 18802
BROWSER_URL = f"http://localhost:{CDP_PORT}"
KEYWORDS = ["AI", "SaaS", "indie hacker", "crypto", "出海", "赚钱", "搞笑", "ship", "growth"]

NODE_TEMPLATE = r"""
const puppeteer = require('puppeteer-core');
(async () => {
  const browser = await puppeteer.connect({ browserURL: '__BROWSER_URL__' });
  const page = await browser.newPage();
  try {
    await page.goto('__SEARCH_URL__', { waitUntil: 'networkidle2', timeout: 45000 });
    await new Promise(r => setTimeout(r, 8000));

    const tweets = await page.evaluate(() => {
      const out = [];
      document.querySelectorAll('[data-testid="tweet"]').forEach(el => {
        const text = el.querySelector('[data-testid="tweetText"]')?.innerText;
        const url = Array.from(el.querySelectorAll('a'))
          .map(a => a.href)
          .find(l => l && l.includes('/status/') && !l.includes('/photo/'));
        if (!text || !url || text.length <= 10) return;
        const s = text.toLowerCase();
        // filter engagement-bait/spam
        if (s.includes('follow') || s.includes('followers') || s.includes('retweet') || s.includes('giveaway') || s.includes('dm me')) return;
        out.push({ text, url: url.split('?')[0] });
      });
      return out;
    });

    console.log(JSON.stringify(tweets));
  } catch (e) {
    console.error(String(e));
  } finally {
    await page.close();
    await browser.disconnect();
  }
})();
"""

async def find_one_viral_tweet():
    # Prefer English-first keywords for better "Top" results; fallback to AI
    q = random.choice(KEYWORDS)
    if not q:
        q = 'AI'
    search_url = f"https://x.com/search?q={quote(q)}&src=typed_query&f=top"

    js = NODE_TEMPLATE.replace('__BROWSER_URL__', BROWSER_URL).replace('__SEARCH_URL__', search_url)
    with open('/tmp/x_viral_finder.js', 'w', encoding='utf-8') as f:
        f.write(js)

    res = subprocess.run(
        ["node", "/tmp/x_viral_finder.js"],
        capture_output=True,
        text=True,
        env={**os.environ, "NODE_PATH": "/tmp/node_modules"},
        timeout=120,
    )

    try:
        data = json.loads(res.stdout or "[]")
    except Exception:
        data = []

    if not data:
        return None

    # Avoid replying to ourselves
    forbidden = ['dashuai38953711']
    data2 = [t for t in data if not any(h in (t.get('url','')) for h in forbidden)]
    if not data2:
        return None

    return random.choice(data2)

async def main():
    target = await find_one_viral_tweet()
    if not target:
        print("FAIL: No target found")
        raise SystemExit(1)

    out_path = '/root/.openclaw/workspace/data/last_viral_target.json'
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(target, f, ensure_ascii=False)

    print(f"SUCCESS: {target['url']}")

if __name__ == "__main__":
    asyncio.run(main())
