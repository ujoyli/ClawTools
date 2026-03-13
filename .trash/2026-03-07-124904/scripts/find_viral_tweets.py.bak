import asyncio
import os
import json
import sys
from urllib.parse import quote
import time
import random

# Configuration - dynamically find CDP port
import socket

def find_chromium_cdp_port():
    """Find Chromium CDP port by scanning common ports or checking BrowserWing"""
    # First try common static ports
    for port in [18802, 32803, 9222]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            result = sock.connect_ex(('127.0.0.1', port))
            sock.close()
            if result == 0:
                # Verify it's a CDP endpoint
                import urllib.request
                try:
                    resp = urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=1)
                    if resp.status == 200:
                        return port
                except:
                    pass
        except:
            pass
    
    # Try to find BrowserWing's dynamic port via netstat
    try:
        import subprocess
        res = subprocess.run(['netstat', '-tlnp'], capture_output=True, text=True, timeout=5)
        for line in res.stdout.split('\n'):
            if 'chrome' in line.lower() or 'chromium' in line.lower():
                parts = line.split()
                for part in parts:
                    if part.startswith('127.0.0.1:'):
                        port = int(part.split(':')[1])
                        # Verify it's CDP
                        import urllib.request
                        try:
                            resp = urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=1)
                            if resp.status == 200:
                                return port
                        except:
                            pass
    except:
        pass
    
    return 18080  # fallback

CDP_PORT = find_chromium_cdp_port()
BROWSER_URL = f"http://localhost:{CDP_PORT}"
# Added English keywords to find broader viral content
KEYWORDS = ["AI", "SaaS", "出海", "赚钱", "搞笑", "indie hacker", "build in public", "solopreneur"]
MAX_REPLIES_PER_RUN = 1

async def find_viral_tweets():
    # Use home timeline instead of search (more reliable, no anti-bot)
    # Look for tweets with high engagement
    search_url = f"https://x.com/home"
    
    print(f"Scanning home timeline for viral tweets...")
    
    node_scraper = f"""
const puppeteer = require('puppeteer-core');
(async () => {{
  const browser = await puppeteer.connect({{ browserURL: '{BROWSER_URL}' }});
  const page = await browser.newPage();
  try {{
    await page.goto('{search_url}', {{ waitUntil: 'domcontentloaded', timeout: 20000 }});
    await new Promise(r => setTimeout(r, 5000));
    
    const tweets = await page.evaluate(() => {{
      const results = [];
      document.querySelectorAll('[data-testid="tweet"]').forEach(el => {{
        const text = el.querySelector('[data-testid="tweetText"]')?.innerText;
        const statusLink = Array.from(el.querySelectorAll('a'))
          .map(a => a.href)
          .find(l => l.includes('/status/') && !l.includes('/photo/'));
        
        // Look for engagement metrics
        const replyCount = el.querySelector('[data-testid="reply"]')?.innerText;
        const retweetCount = el.querySelector('[data-testid="retweet"]')?.innerText;
        const likeCount = el.querySelector('[data-testid="like"]')?.innerText;
        
        // Parse like count (handle "1.2K", "10K", etc.)
        let likes = 0;
        if (likeCount) {{
          const match = likeCount.replace(/,/g, '').match(/([\\d.]+)([KMB])?/i);
          if (match) {{
            const num = parseFloat(match[1]);
            const suffix = (match[2] || '').toLowerCase();
            if (suffix === 'k') likes = num * 1000;
            else if (suffix === 'm') likes = num * 1000000;
            else if (suffix === 'b') likes = num * 1000000000;
            else likes = num;
          }}
        }}
        
        // Consider tweets with 50+ likes as potentially viral
        if (text && statusLink && likes >= 50) {{
          results.push({{ text, url: statusLink.split('?')[0], likes, retweetCount, replyCount }});
        }}
      }});
      return results;
    }});
    console.log(JSON.stringify(tweets));
  }} catch (e) {{
    console.error(e);
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
        # Blacklist - never reply to these accounts
        blacklist = ["whyyoutouzhele", "teacherli1", "liteacher", "lixiansheng"]
        
        print(f"Raw data: {len(data)} tweets found")
        # Filter: short tweets + blacklisted accounts
        valid = [
            t for t in data 
            if len(t.get('text', '')) > 20 
            and t.get('handle', '').lower() not in blacklist
        ]
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

    # Pick the best one (or random for variety)
    target = random.choice(tweets)
    
    with open('/root/.openclaw/workspace/data/viral_targets.json', 'w') as f:
        json.dump([target], f, ensure_ascii=False, indent=2)
    
    print(f"FOUND_TARGET: {target['url']}")

if __name__ == "__main__":
    asyncio.run(main())
