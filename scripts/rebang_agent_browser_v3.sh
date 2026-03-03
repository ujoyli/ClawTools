#!/usr/bin/env bash
set -euo pipefail

# Rebang hot item poster using agent-browser
# 1. Pick item from rebang (via puppeteer CDP - more reliable)
# 2. Fetch content and image from Hupu
# 3. Post to X (via puppeteer with cookie injection)

# Setup logging
LOG_DIR="/var/log/openclaw"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/rebang_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to log file AND stdout
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "=== REBANG TASK STARTED AT $(date) ==="
echo "Log file: $LOG_FILE"

WORKDIR="/root/.openclaw/workspace"
CACHE_JSON="$WORKDIR/data/rebang_posted.json"
SENT_DB="$WORKDIR/data/rebang_sent.db"
PICK_CDP_PORT=44407
POST_CDP_PORT=44407
ab() { agent-browser --cdp "$PICK_CDP_PORT" "$@"; }

export WORKDIR PICK_CDP_PORT POST_CDP_PORT SENT_DB

# Ensure Chromium/BrowserWing is running (same as other cron jobs)
echo "Starting Chromium/BrowserWing..."
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_rebang.log 2>&1 || true
sleep 5

# Pick an item from rebang via puppeteer (CDP is more reliable for complex sites)
echo "Picking rebang item..."
python3 - <<'PY' > /tmp/rebang_pick.json
import os, json, time, hashlib, re, subprocess

cache_path = '/root/.openclaw/workspace/data/rebang_posted.json'
sent_db = os.environ.get('SENT_DB', '/root/.openclaw/workspace/data/rebang_sent.db')
now = int(time.time())
window = 24 * 3600
CDP_PORT = int(os.environ.get('PICK_CDP_PORT', '44407'))

cache = {}
try:
    cache = json.load(open(cache_path, 'r', encoding='utf-8'))
except:
    cache = {}
posted = cache.get('posted', {}) if isinstance(cache, dict) else {}

import sqlite3
conn = sqlite3.connect(sent_db)
conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url TEXT PRIMARY KEY, sent_at INTEGER NOT NULL)')
conn.commit()

def canonical_url(u: str) -> str:
    u = (u or '').strip()
    u = re.sub(r'#.*$', '', u)
    u = re.sub(r'\?.*$', '', u)
    return u

def was_sent_recent(u: str, sec: int) -> bool:
    cu = canonical_url(u)
    if not cu:
        return False
    row = conn.execute('SELECT sent_at FROM sent_urls WHERE url=?', (cu,)).fetchone()
    return bool(row and (now - int(row[0])) < sec)

# Use puppeteer via CDP
node_script = """
const puppeteer = require('puppeteer-core');
const CDP_PORT = process.env.CDP_PORT || '44407';

function pickContentImage(doc) {
  const bad = /(avatar|logo|icon|emoji|sprite|ads?|banner|qr)/i;
  // prioritize images inside thread-content-detail (正文)，then fallback to broad selectors
  const imgs = [...doc.querySelectorAll('.thread-content-detail img, article img, .post img, .content img, .article img, main img, .thread img, .bbs-post img, img')];
  for (const img of imgs) {
    let src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-origin') || img.getAttribute('data-original') || '';
    if (!src) {
      const ss = img.getAttribute('srcset') || '';
      if (ss.includes('http')) src = ss.split(',')[0].trim().split(' ')[0];
    }
    if (!src || !/^https?:\/\//.test(src)) continue;
    const alt = (img.alt || '') + ' ' + (img.className || '') + ' ' + (img.id || '');
    if (bad.test(alt) || bad.test(src)) continue;
    const w = img.naturalWidth || img.width || 0;
    const h = img.naturalHeight || img.height || 0;
    if ((w && w < 180) || (h && h < 140)) continue;
    return src;
  }
  return '';
}

(async () => {
  const log = (msg) => console.error('[DEBUG]', msg);
  
  try {
    const browser = await puppeteer.connect({browserURL: 'http://localhost:' + CDP_PORT});
    const pages = await browser.pages();
    const page = pages.length > 0 ? pages[0] : await browser.newPage();

    // Try rebang.today first
    log('Fetching rebang.today/?tab=hupu...');
    await page.goto('https://rebang.today/?tab=hupu', {waitUntil: 'networkidle2', timeout: 60000});
    
    // Wait for React app to render - check for content multiple times
    log('Waiting for content to render...');
    let seeds = [];
    for (let attempt = 1; attempt <= 6; attempt++) {
      await new Promise(r => setTimeout(r, 5000)); // Wait 5s between checks
      
      seeds = await page.evaluate(() => {
        const out = [];
        const seen = new Set();
        // Look for links in the main content area first
        const links = document.querySelectorAll('a[href*="hupu"], a[href*="/go/"]');
        links.forEach(a => {
          const href = (a.href || '').trim();
          const text = (a.textContent || '').trim().replace(/\\s+/g, ' ');
          if (!href || !href.startsWith('http')) return;
          if (text.length < 5) return; // Lower threshold
          if (seen.has(href)) return;
          seen.add(href);
          out.push({href, text});
        });
        return out.slice(0, 20);
      });
      
      log(`Check ${attempt}: found ${seeds.length} seeds`);
      if (seeds.length > 0) break;
    }
    
    log(`First phase: found ${seeds.length} seeds`);
    
    // Retry once if empty
    if (seeds.length === 0) {
      log('Retrying with longer wait...');
      await page.reload({waitUntil: 'networkidle2', timeout: 60000});
      await new Promise(r => setTimeout(r, 20000));
      
      seeds = await page.evaluate(() => {
        const out = [];
        const seen = new Set();
        document.querySelectorAll('a').forEach(a => {
          const href = (a.href || '').trim();
          const text = (a.textContent || '').trim().replace(/\\s+/g, ' ');
          if (!href || !href.startsWith('http') || text.length < 8) return;
          if (!/hupu|rebang\.today\/go|bbs/i.test(href)) return;
          if (seen.has(href)) return;
          seen.add(href);
          out.push({href, text});
        });
        return out.slice(0, 20);
      });
      
      log(`Retry attempt: found ${seeds.length} seeds`);
    }
    
    // Fallback: direct hupu hot posts if still empty
    if (seeds.length === 0) {
      log('Falling back to hupu.com directly...');
      try {
        await page.goto('https://bbs.hupu.com/all-gambia', {waitUntil: 'domcontentloaded', timeout: 60000});
        await new Promise(r => setTimeout(r, 15000));
        
        seeds = await page.evaluate(() => {
          const out = [];
          const seen = new Set();
          // Look for post links
          document.querySelectorAll('a[href*="/"]').forEach(a => {
            const href = (a.href || '').trim();
            const text = (a.textContent || '').trim().replace(/\\s+/g, ' ');
            if (!href || !href.match(/bbs\.hupu\.com\/\d+\.html$/)) return;
            if (text.length < 10 || text.length > 100) return;
            if (seen.has(href)) return;
            seen.add(href);
            out.push({href, text});
          });
          return out.slice(0, 15);
        });
        
        log(`Hupu fallback: found ${seeds.length} seeds`);
      } catch (e) {
        log('Hupu fallback failed: ' + e.message);
      }
    }
    
    log(`Final seed count: ${seeds.length}`);
    if (seeds.length === 0) {
      log('Page title: ' + await page.title());
      log('Current URL: ' + page.url());
    }

    const out = [];
    for (const it of seeds) {
      const p = await browser.newPage();
      try {
        await p.goto(it.href, {waitUntil: 'domcontentloaded', timeout: 45000});
        await new Promise(r => setTimeout(r, 10000));
        let image = await p.evaluate(() => {
          const bad = /(avatar|logo|icon|emoji|sprite|ads?|banner|qr)/i;
          const scope = document.querySelector('.thread-content-detail') || document;
          const imgs = [...scope.querySelectorAll('img, picture img, source')];
          for (const img of imgs) {
            let src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-origin') || img.getAttribute('data-original') || img.getAttribute('data-srcset') || '';
            if (!src) {
              const ss = img.getAttribute('srcset') || '';
              if (ss.includes('http')) src = ss.split(',')[0].trim().split(' ')[0];
            }
            if (!src || !/^https?:\/\//.test(src)) continue;
            const alt = (img.alt || '') + ' ' + (img.className || '') + ' ' + (img.id || '');
            if (bad.test(alt) || bad.test(src)) continue;
            const w = img.naturalWidth || img.width || 0;
            const h = img.naturalHeight || img.height || 0;
            // accept when dimensions are unknown (0) to avoid false negatives in headless
            if ((w && w < 180) || (h && h < 140)) continue;
            return src;
          }
          const pic = scope.querySelector('picture');
          if (pic) {
            const s = pic.querySelector('source[srcset]');
            if (s) {
              const ss = s.getAttribute('srcset') || '';
              if (ss.includes('http')) return ss.split(',')[0].trim().split(' ')[0];
            }
          }
          const els = [...scope.querySelectorAll('*')];
          for (const el of els) {
            const bg = window.getComputedStyle(el).getPropertyValue('background-image') || '';
            const m = bg.match(/url\(([^)]+)\)/);
            if (m) {
              let u = m[1].replace(/\"|\'/g, '');
              if (u.startsWith('http')) return u;
            }
          }
          return '';
        });
        // retry once after short wait if empty
        if (!image) {
          await new Promise(r => setTimeout(r, 3000));
          image = await p.evaluate(() => {
            const bad = /(avatar|logo|icon|emoji|sprite|ads?|banner|qr)/i;
            const scope = document.querySelector('.thread-content-detail') || document;
            const imgs = [...scope.querySelectorAll('img, picture img, source')];
            for (const img of imgs) {
              let src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-origin') || img.getAttribute('data-original') || img.getAttribute('data-srcset') || '';
              if (!src) {
                const ss = img.getAttribute('srcset') || '';
                if (ss.includes('http')) src = ss.split(',')[0].trim().split(' ')[0];
              }
              if (!src || !/^https?:\/\//.test(src)) continue;
              const alt = (img.alt || '') + ' ' + (img.className || '') + ' ' + (img.id || '');
              if (bad.test(alt) || bad.test(src)) continue;
              const w = img.naturalWidth || img.width || 0;
              const h = img.naturalHeight || img.height || 0;
              if ((w && w < 180) || (h && h < 140)) continue;
              return src;
            }
            const pic = scope.querySelector('picture');
            if (pic) {
              const s = pic.querySelector('source[srcset]');
              if (s) {
                const ss = s.getAttribute('srcset') || '';
                if (ss.includes('http')) return ss.split(',')[0].trim().split(' ')[0];
              }
            }
            const els = [...scope.querySelectorAll('*')];
            for (const el of els) {
              const bg = window.getComputedStyle(el).getPropertyValue('background-image') || '';
              const m = bg.match(/url\(([^)]+)\)/);
              if (m) {
                let u = m[1].replace(/\"|\'/g, '');
                if (u.startsWith('http')) return u;
              }
            }
            return '';
          });
        }
        out.push({href: it.href, text: it.text, image: image || ''});
      } catch (e) {
      } finally {
        await p.close();
      }
      if (out.length >= 8) break;
    }

    console.log(JSON.stringify(out));
    await browser.disconnect();
  } catch (e) {
    console.error('ERROR:', e.message);
    console.log('[]');
  }
})();
"""

env = os.environ.copy()
env['NODE_PATH'] = '/tmp/node_modules'
env['CDP_PORT'] = str(CDP_PORT)
result = subprocess.run(['node', '-e', node_script], capture_output=True, text=True, env=env, timeout=240)

# Parse JSON from stdout robustly
items = []
stdout = (result.stdout or '').strip()
if stdout:
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            try:
                items = json.loads(line)
                break
            except:
                pass

if not items:
    # fallback: search first JSON array fragment in stdout only
    import re
    m = re.search(r'\[[\s\S]*\]', stdout)
    if m:
        try:
            items = json.loads(m.group())
        except:
            items = []

def key_for(it):
    # Strong dedupe by canonical URL first (title on rebang/hupu may drift)
    u = (it.get('href', '') or '').strip()
    u = re.sub(r'#.*$', '', u)
    u = re.sub(r'\?.*$', '', u)
    t = re.sub(r'\s+', ' ', (it.get('text', '') or '').strip())
    base = u if u else t
    return hashlib.sha1(base.encode('utf-8', 'ignore')).hexdigest()

# Filter out political topics
political_keywords = [
    '习近平','中共','共产党','国务院','人大','政协','政治','政坛','官员','外交','制裁','联合国',
    '总统','总理','议会','选举','政府','内阁','民主党','共和党','国会','白宫','北约','欧盟',
    '以色列','巴勒斯坦','伊朗','哈梅内伊','俄乌','俄罗斯','乌克兰','台海','台湾','香港','南海'
]

def is_political(it):
    t = (it.get('text','') or '').lower()
    return any(k.lower() in t for k in political_keywords)

items = [it for it in items if not is_political(it)]

# Prefer non-douyin hot links first
preferred = [it for it in items if 'douyin.com' not in it.get('href','') and '/video/' not in it.get('href','')]
fallback = [it for it in items if it not in preferred]

picked = None
for bucket in (preferred, fallback):
    for it in bucket:
        k = key_for(it)
        ts = posted.get(k, 0)
        url_ok = not was_sent_recent(it.get('href', ''), window)
        key_ok = (not ts or now - ts > window)
        if url_ok and key_ok:
            picked = it
            picked['_key'] = k
            break
    if picked:
        break

import sys
conn.close()
print(f"DEBUG: Found {len(items)} items", file=sys.stderr)
if not items:
    print(json.dumps({'ok': False, 'error': 'no items found'}))
elif not picked:
    print(f"DEBUG: All items posted within window, skip this run", file=sys.stderr)
    print(json.dumps({'ok': False, 'error': 'all items already posted in window'}))
else:
    print(f"DEBUG: Found unposted item", file=sys.stderr)
    print(json.dumps({'ok': True, 'dedupe': 'ok', 'title': picked['text'][:180], 'url': picked['href'], 'image': picked.get('image',''), 'key': picked['_key']}, ensure_ascii=False))
PY

PICK_RESULT=$(cat /tmp/rebang_pick.json)
OK=$(python3 -c "import json; print('1' if json.loads('$PICK_RESULT').get('ok') else '0')" 2>/dev/null || echo "0")

if [[ "$OK" != "1" ]]; then
  echo "Pick failed: $PICK_RESULT" >&2
  exit 1
fi

TITLE=$(python3 - <<'PY'
import json,re
s=json.load(open('/tmp/rebang_pick.json'))['title']
s=re.sub(r'\s+',' ',s).strip()
# 去重：如果前后两半完全一致，压成一半
n=len(s)
if n>=20 and n%2==0 and s[:n//2]==s[n//2:]:
    s=s[:n//2]
# 去重：相同问句重复两次
m=re.match(r'^(.*?[？?])\1+$', s)
if m:
    s=m.group(1)
print(s)
PY
)
URL=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d['url'])")
IMAGE_URL=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d.get('image',''))")
KEY=$(python3 -c "import json; d=json.load(open('/tmp/rebang_pick.json')); print(d.get('key',''))")
export KEY

echo "Selected: ${TITLE:0:60}..."

# Fetch content (title, body, image) from Hupu page
echo "Fetching content from Hupu..."
CONTENT_OUT=$(python3 "$WORKDIR/scripts/get_img_from_hupu.py" "$URL" 2>/tmp/get_img_debug.log)
HUPU_TITLE=$(echo "$CONTENT_OUT" | awk '/^TITLE /{print substr($0,7); exit}')
HUPU_BODY=$(echo "$CONTENT_OUT" | awk '/^BODY /{print substr($0,6); exit}')
IMG_PATH=$(echo "$CONTENT_OUT" | awk '/^SAVED /{print substr($0,7); exit}')
IMAGE_URL=$(echo "$CONTENT_OUT" | awk '/^SRC /{print substr($0,5); exit}')

if [[ -z "$IMG_PATH" ]]; then
  echo "ERROR: Failed to fetch image from $URL"
  exit 1
fi

echo "Image ready: $IMG_PATH"
echo "Body length: ${#HUPU_BODY} chars"

# Condense body if > 100 chars using subagent
BODY_FOR_TWEET="$HUPU_BODY"
if [[ ${#HUPU_BODY} -gt 100 ]]; then
  echo "Body > 100 chars, condensing via subagent..."
  BODY_FOR_TWEET=$(python3 - <<'CONDENSE_PY'
import os, subprocess, json
body = os.environ.get('HUPU_BODY', '')
prompt = f"""请将以下正文浓缩到100字以内，保留核心信息：

{body}

要求：
- 严格控制在100字以内
- 保留关键事实和观点
- 语言流畅自然
- 直接返回浓缩后的文本，不要添加任何解释
"""
try:
    result = subprocess.run(
        ['openclaw', 'agent', '--session-id', 'x-rebang-condense', '--thinking', 'minimal', '--json', '--message', prompt],
        capture_output=True, text=True, timeout=60
    )
    if result.returncode == 0:
        obj = json.loads(result.stdout)
        text = obj.get('result', {}).get('payloads', [{}])[0].get('text', '').strip()
        # Ensure <= 100 chars
        if len(text) > 100:
            text = text[:97] + '...'
        print(text)
    else:
        # Fallback: truncate
        print(body[:97] + '...' if len(body) > 100 else body)
except Exception:
    print(body[:97] + '...' if len(body) > 100 else body)
CONDENSE_PY
)
fi

# Generate tags from title
TAGS=$(python3 - <<'TAGS_PY'
import os, re
title = os.environ.get('HUPU_TITLE', '')
# Extract keywords for tags
kws = re.findall(r'[\u4e00-\u9fff]{2,4}', title)[:3]
if not kws:
    kws = ['热点', '虎扑']
tags = ' '.join([f'#{k}' for k in kws[:3]])
print(tags)
TAGS_PY
)

# Format tweet: Title + Body + Tags (no URL)
TEXT="${HUPU_TITLE}

${BODY_FOR_TWEET}

${TAGS}"

export TEXT
export IMG_PATH
echo "Tweet text preview:"
echo "${TEXT:0:100}..."

# Post to X in a single Puppeteer CDP context (cookie inject + compose + upload + post)
echo "Posting to X..."
TWEET_RESULT=$(NODE_PATH=/tmp/node_modules TEXT="$TEXT" IMG_PATH="$IMG_PATH" CDP_PORT="$POST_CDP_PORT" node - <<'NODE'
const fs = require('fs');
const puppeteer = require('puppeteer-core');

const log = (msg) => {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${msg}`);
};

const result = { success: false, tweetId: null, error: null, screenshots: [] };

(async () => {
  const text = process.env.TEXT || '';
  const imagePath = process.env.IMG_PATH;
  const cdpPort = process.env.CDP_PORT || '44407';
  const cookiesPath = '/root/x_cookies.json';
  const screenshotDir = '/root/.openclaw/workspace/tmp';

  log('Starting X post workflow');
  log(`Text length: ${text.length} chars`);
  log(`Image path: ${imagePath}`);

  if (!text.trim()) {
    result.error = 'Empty tweet text';
    log('ERROR: Empty tweet text');
    console.log(JSON.stringify(result));
    process.exit(1);
  }
  
  if (!imagePath || !fs.existsSync(imagePath)) {
    result.error = 'Image file not found: ' + imagePath;
    log('ERROR: Image file not found');
    console.log(JSON.stringify(result));
    process.exit(1);
  }
  
  if (!fs.existsSync(cookiesPath)) {
    result.error = 'Missing /root/x_cookies.json';
    log('ERROR: Missing cookies file');
    console.log(JSON.stringify(result));
    process.exit(1);
  }

  const cookiesRaw = JSON.parse(fs.readFileSync(cookiesPath, 'utf8'));
  const cookies = (Array.isArray(cookiesRaw) ? cookiesRaw : []).map(c => ({
    name: c.name,
    value: c.value,
    domain: c.domain,
    path: c.path || '/',
    httpOnly: !!c.httpOnly,
    secure: !!c.secure,
    sameSite: c.sameSite === 'no_restriction' ? 'None' : (c.sameSite === 'lax' ? 'Lax' : (c.sameSite === 'strict' ? 'Strict' : undefined)),
    expires: Number.isFinite(c.expirationDate) ? c.expirationDate : undefined,
  })).filter(c => c.name && c.value && c.domain);

  log(`Loaded ${cookies.length} cookies`);

  let browser;
  try {
    browser = await puppeteer.connect({ browserURL: `http://localhost:${cdpPort}` });
    log('Connected to browser');
  } catch (e) {
    result.error = 'Failed to connect to browser: ' + e.message;
    log('ERROR: ' + result.error);
    console.log(JSON.stringify(result));
    process.exit(1);
  }

  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  let page;
  
  const saveScreenshot = async (name) => {
    const path = `${screenshotDir}/x_${name}_${Date.now()}.png`;
    try {
      await page.screenshot({ path, fullPage: true });
      result.screenshots.push(path);
      log(`Screenshot saved: ${path}`);
    } catch (e) {
      log(`Failed to save screenshot: ${e.message}`);
    }
  };

  try {
    const pages = await browser.pages();
    page = pages.length > 0 ? pages[0] : await browser.newPage();
    log('Got page handle');

    // Navigate to home
    log('Navigating to x.com/home');
    try {
      await page.goto('https://x.com/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
    } catch (_) {
      await page.goto('https://twitter.com/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
    }
    log('Home page loaded');

    // Set cookies
    await page.setCookie(...cookies);
    log(`Injected ${cookies.length} cookies`);

    // Refresh to apply cookies
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 60000 });
    log('Page reloaded with cookies');
    await sleep(2500);

    // Navigate to compose
    log('Opening compose page');
    try {
      await page.goto('https://x.com/compose/post', { waitUntil: 'domcontentloaded', timeout: 60000 });
    } catch (_) {
      await page.goto('https://twitter.com/compose/post', { waitUntil: 'domcontentloaded', timeout: 60000 });
    }
    log('Compose page loaded');
    await sleep(5000);

    // Check if logged in
    const composerSel = '[data-testid="tweetTextarea_0_label"], div[role="textbox"][data-testid="tweetTextarea_0"]';
    await page.waitForSelector(composerSel, { timeout: 25000 }).catch(() => null);
    const composer = await page.$(composerSel);
    
    if (!composer) {
      result.error = 'Not logged in to X after cookie injection';
      log('ERROR: ' + result.error);
      await saveScreenshot('not_logged_in');
      console.log(JSON.stringify(result));
      process.exit(1);
    }
    log('Composer found, logged in confirmed');

    // Type text
    await composer.click();
    await page.keyboard.type(text, { delay: 10 });
    log('Text typed into composer');

    // Upload image
    const fileInput = await page.$('input[type="file"][data-testid="fileInput"]')
      || await page.$('input[type="file"]')
      || await page.$('input[accept*="image"]');
    
    if (!fileInput) {
      result.error = 'File input not found on compose page';
      log('ERROR: ' + result.error);
      await saveScreenshot('no_file_input');
      console.log(JSON.stringify(result));
      process.exit(1);
    }

    await fileInput.uploadFile(imagePath);
    log('Image uploaded');
    await sleep(9000);

    // Verify attachment
    const attachments = await page.$('[data-testid="attachments"]');
    if (!attachments) {
      result.error = 'Image upload not confirmed (no media preview)';
      log('ERROR: ' + result.error);
      await saveScreenshot('no_attachment_preview');
      console.log(JSON.stringify(result));
      process.exit(1);
    }
    log('Attachment preview confirmed');

    // Find tweet button
    const tweetBtn = await page.$('[data-testid="tweetButton"]') || await page.$('[data-testid="tweetButtonInline"]');
    if (!tweetBtn) {
      result.error = 'Tweet button not found';
      log('ERROR: ' + result.error);
      await saveScreenshot('no_tweet_button');
      console.log(JSON.stringify(result));
      process.exit(1);
    }

    // Check if disabled
    const disabled = await page.evaluate(el => !!el.disabled || el.getAttribute('aria-disabled') === 'true', tweetBtn);
    if (disabled) {
      result.error = 'Tweet button is disabled';
      log('ERROR: ' + result.error);
      await saveScreenshot('button_disabled');
      console.log(JSON.stringify(result));
      process.exit(1);
    }
    log('Tweet button enabled');

    // Get current URL before posting
    const prePostUrl = page.url();
    log(`Pre-post URL: ${prePostUrl}`);

    // Click tweet button
    log('Clicking tweet button');
    await tweetBtn.click();
    
    // Wait for navigation or confirmation
    log('Waiting for post completion...');
    await sleep(8000);

    // Check current URL for tweet ID
    const postPostUrl = page.url();
    log(`Post-post URL: ${postPostUrl}`);

    // Try to extract tweet ID from URL
    const statusMatch = postPostUrl.match(/\/status\/(\d+)/);
    if (statusMatch) {
      result.tweetId = statusMatch[1];
      result.success = true;
      log(`SUCCESS: Tweet posted with ID ${result.tweetId}`);
    } else if (postPostUrl !== prePostUrl && postPostUrl.includes('/status/')) {
      // URL changed and contains status
      const idMatch = postPostUrl.match(/(\d{10,})/);
      if (idMatch) {
        result.tweetId = idMatch[1];
        result.success = true;
        log(`SUCCESS: Tweet posted with ID ${result.tweetId}`);
      }
    }

    // If no tweet ID found, check for success indicators
    if (!result.success) {
      // Look for success toast or notification
      const successIndicator = await page.$('[data-testid="toast"], [role="alert"], .toast');
      if (successIndicator) {
        const indicatorText = await page.evaluate(el => el.textContent, successIndicator);
        log(`Found indicator: ${indicatorText}`);
        if (indicatorText.toLowerCase().includes('sent') || indicatorText.toLowerCase().includes('posted')) {
          result.success = true;
          result.tweetId = 'unknown_' + Date.now();
          log('SUCCESS: Found success indicator');
        }
      }
    }

    // Final verification
    if (!result.success) {
      result.error = 'Tweet ID not found after posting';
      log('ERROR: ' + result.error);
      await saveScreenshot('post_failed');
      console.log(JSON.stringify(result));
      process.exit(1);
    }

    // Save success screenshot
    await saveScreenshot('post_success');
    
    // Output result as JSON
    console.log(JSON.stringify(result));
    log('Workflow completed successfully');

  } catch (e) {
    result.error = 'Unexpected error: ' + e.message;
    log('ERROR: ' + result.error);
    try {
      await saveScreenshot('unexpected_error');
    } catch (_) {}
    console.log(JSON.stringify(result));
    process.exit(1);
  } finally {
    if (browser) {
      await browser.disconnect();
      log('Browser disconnected');
    }
  }
})();
NODE
)

# Parse result
if [[ -z "$TWEET_RESULT" ]]; then
  echo "ERROR: No result from X posting"
  exit 1
fi

echo "Raw result: $TWEET_RESULT"

TWEET_ID=$(echo "$TWEET_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tweetId',''))")
SUCCESS=$(echo "$TWEET_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))")
ERROR_MSG=$(echo "$TWEET_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error',''))")

if [[ "$SUCCESS" != "True" ]] || [[ -z "$TWEET_ID" ]]; then
  echo "ERROR: Failed to post tweet"
  echo "Error message: $ERROR_MSG"
  exit 1
fi

echo "SUCCESS: Tweet posted with ID: $TWEET_ID"
export TWEET_ID

# Mark as posted (JSON + SQLite URL dedupe)
python3 - <<'PY'
import json, time, os, re, sqlite3

cache = {'posted': {}}
cache_path = '/root/.openclaw/workspace/data/rebang_posted.json'
sent_db = os.environ.get('SENT_DB', '/root/.openclaw/workspace/data/rebang_sent.db')
try:
    cache = json.load(open(cache_path,'r',encoding='utf-8'))
except:
    pass

key = os.environ.get('KEY', '')
url = (os.environ.get('URL', '') or '').strip()
url = re.sub(r'#.*$', '', url)
url = re.sub(r'\?.*$', '', url)
now = int(time.time())

if key:
    cache['posted'][key] = now
    cache['posted'] = {k: v for k, v in cache['posted'].items() if (now - int(v)) < 7*24*3600}
    with open(cache_path, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)
        f.write('\n')

if url:
    conn = sqlite3.connect(sent_db)
    conn.execute('CREATE TABLE IF NOT EXISTS sent_urls (url TEXT PRIMARY KEY, sent_at INTEGER NOT NULL)')
    conn.execute('INSERT INTO sent_urls(url, sent_at) VALUES(?, ?) ON CONFLICT(url) DO UPDATE SET sent_at=excluded.sent_at', (url, now))
    conn.commit()
    conn.close()

print('✓ Marked as posted')
PY

ab close
echo "✓ Done!"
