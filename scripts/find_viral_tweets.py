import asyncio
import os
import json
import sys
import time
import random
import socket
from datetime import datetime, timezone


def find_chromium_cdp_port():
    """Find Chromium CDP port by scanning common ports or checking BrowserWing"""
    for port in [44407, 18802, 32803, 9222]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            result = sock.connect_ex(('127.0.0.1', port))
            sock.close()
            if result == 0:
                import urllib.request
                try:
                    resp = urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=1)
                    if resp.status == 200:
                        return port
                except Exception:
                    pass
        except Exception:
            pass
    return 44407


CDP_PORT = find_chromium_cdp_port()
BROWSER_URL = f"http://localhost:{CDP_PORT}"


def compute_age_min(iso_time: str) -> float:
    if not iso_time:
        return 99999.0
    try:
        dt = datetime.fromisoformat(iso_time.replace('Z', '+00:00'))
        return max(1.0, (datetime.now(timezone.utc) - dt).total_seconds() / 60.0)
    except Exception:
        return 99999.0


async def find_viral_tweets():
    search_url = "https://x.com/home"
    print("Scanning home timeline for viral tweets...")

    node_scraper = f"""
const puppeteer = require('puppeteer-core');
const fs = require('fs');
(async()=>{{
  const browser = await puppeteer.connect({{ browserURL: '{BROWSER_URL}' }});
  const page = await browser.newPage();
  try {{
    const cookies = JSON.parse(fs.readFileSync('/home/browserwing/cookie.json', 'utf8'));
    await page.setCookie(...cookies);
  }} catch (e) {{}}

  try {{
    await page.goto('{search_url}', {{ waitUntil: 'domcontentloaded', timeout: 30000 }});
    await new Promise(r => setTimeout(r, 8000));

    const tweets = await page.evaluate(() => {{
      const parseCount = (s) => {{
        s = (s || '').replace(/,/g, '').trim();
        const m = s.match(/([\d.]+)([KMB])?/i);
        if (!m) return 0;
        let v = parseFloat(m[1]);
        const u = (m[2] || '').toUpperCase();
        if (u === 'K') v *= 1000;
        else if (u === 'M') v *= 1000000;
        else if (u === 'B') v *= 1000000000;
        return Math.floor(v);
      }};

      return [...document.querySelectorAll('article[data-testid="tweet"]')].slice(0, 60).map(el => {{
        const text = (el.querySelector('[data-testid="tweetText"]')?.innerText || '').trim();
        const time = el.querySelector('time')?.getAttribute('datetime') || '';
        const timeLink = [...el.querySelectorAll('a[href*="/status/"]')].find(a => a.querySelector('time'));
        const statusLink = timeLink ? timeLink.href : '';
        const tid = (statusLink.match(/status\/(\d+)/) || [])[1] || '';
        const handle = (statusLink.match(/x\.com\/([^/]+)\/status\//) || [])[1] || '';

        const group = el.querySelector('[role="group"]');
        const label = group ? (group.getAttribute('aria-label') || '') : '';
        let views = 0;
        let likes = 0;
        const zhViews = label.match(/(\d[\d\.,KMB]*)\s*次观看/i);
        const enViews = label.match(/(\d[\d\.,KMB]*)\s*view/i);
        const zhLikes = label.match(/(\d[\d\.,KMB]*)\s*喜欢/i);
        const enLikes = label.match(/(\d[\d\.,KMB]*)\s*like/i);
        if (zhViews) views = parseCount(zhViews[1]);
        else if (enViews) views = parseCount(enViews[1]);
        if (zhLikes) likes = parseCount(zhLikes[1]);
        else if (enLikes) likes = parseCount(enLikes[1]);

        return {{ text, time, url: statusLink, tid, handle, views, likes, label }};
      }}).filter(t => t.url && t.tid && t.handle && t.text.length >= 12);
    }});

    console.log(JSON.stringify(tweets));
  }} catch (e) {{
    console.error('Error:', e.message);
    console.log('[]');
  }} finally {{
    await page.close();
    await browser.disconnect();
  }}
}})();
"""

    with open('/tmp/x_scraper.js', 'w') as f:
        f.write(node_scraper)

    import subprocess
    res = subprocess.run(["node", "/tmp/x_scraper.js"], capture_output=True, text=True, env={**os.environ, "NODE_PATH": "/tmp/node_modules"})

    try:
        data = json.loads(res.stdout or "[]")
        blacklist = ["whyyoutouzhele", "teacherli1", "liteacher", "lixiansheng"]
        print(f"Raw data: {len(data)} tweets found")
        valid = []
        for t in data:
            if len(t.get('text', '')) <= 20:
                continue
            if t.get('handle', '').lower() in blacklist:
                continue
            t['ageMin'] = round(compute_age_min(t.get('time', '')), 1)
            valid.append(t)
        print(f"Valid tweets: {len(valid)}")
        return valid
    except Exception as e:
        print(f"Parse error: {e}")
        print(f"stdout: {res.stdout}")
        return []


async def main():
    tweets = await find_viral_tweets()
    if not tweets:
        print("No viral tweets found.")
        return

    # Prefer higher views, then likes, then recency
    tweets.sort(key=lambda t: (t.get('views', 0), t.get('likes', 0), -t.get('ageMin', 99999)), reverse=True)
    target = tweets[0]

    with open('/root/.openclaw/workspace/data/viral_targets.json', 'w') as f:
        json.dump([target], f, ensure_ascii=False, indent=2)

    print(f"FOUND_TARGET: {target['url']}")


if __name__ == "__main__":
    asyncio.run(main())
