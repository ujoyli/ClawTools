#!/usr/bin/env node
/*
  Get view count for a tweet URL via CDP.
  Usage:
    NODE_PATH=/tmp/node_modules node scripts/x_get_views.js <tweet_url> [--port 18802]
  Output JSON: { ok, url, views, raw }
*/

const { connect, goto, sleep } = require('../skills/x-cdp/scripts/lib/cdp-utils');

function parseArgs(argv) {
  const out = { url: '', port: 18802 };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (!out.url && !a.startsWith('--')) out.url = a;
    else if (a === '--port') out.port = Number(argv[++i] || 18802);
  }
  return out;
}

function parseViewsFromText(t) {
  if (!t) return null;
  // Examples:
  // "12.3K Views" / "1,234 Views" / "12万 次观看" / "观看 1,234"
  const s = t.replace(/\u00a0/g, ' ');

  // English
  let m = s.match(/([0-9][0-9,]*\.?[0-9]*)\s*([KMB])?\s*Views/i);
  if (m) {
    let num = parseFloat(m[1].replace(/,/g, ''));
    const u = (m[2] || '').toUpperCase();
    if (u === 'K') num *= 1e3;
    if (u === 'M') num *= 1e6;
    if (u === 'B') num *= 1e9;
    return Math.round(num);
  }

  // Chinese: "12万 次观看" or "1.2万 次观看"
  m = s.match(/([0-9][0-9,]*\.?[0-9]*)\s*(万|亿)?\s*(次观看|观看)/);
  if (m) {
    let num = parseFloat(m[1].replace(/,/g, ''));
    const u = m[2];
    if (u === '万') num *= 1e4;
    if (u === '亿') num *= 1e8;
    return Math.round(num);
  }

  // Fallback: look for line containing Views/次观看 then extract a number
  const lines = s.split(/\n+/).map(x => x.trim()).filter(Boolean);
  const hit = lines.find(l => /Views/i.test(l) || /次观看|观看/.test(l));
  if (hit) {
    const n = hit.match(/([0-9][0-9,]*\.?[0-9]*)/);
    if (n) return Math.round(parseFloat(n[1].replace(/,/g, '')));
  }

  // Last resort: sometimes the first visible number on the page is the view count (e.g. "8.2万"),
  // especially when labels are hidden. If the very first non-empty line is a number-ish token, use it.
  const first = lines[0] || '';
  let mm = first.match(/^([0-9][0-9,]*\.?[0-9]*)\s*(万|亿)?$/);
  if (mm) {
    let num = parseFloat(mm[1].replace(/,/g,''));
    if (mm[2] === '万') num *= 1e4;
    if (mm[2] === '亿') num *= 1e8;
    return Math.round(num);
  }

  return null;
}

(async () => {
  const args = parseArgs(process.argv);
  if (!args.url) {
    console.error('Usage: node x_get_views.js <tweet_url> [--port 18802]');
    process.exit(2);
  }

  const MAX_TRIES = 3;
  let attempt = 0;
  let lastError = null;

  while (attempt < MAX_TRIES) {
    attempt++;
    const backoff = 1000 * attempt;
    let browser, page;
    try {
      const conn = await connect(args.port);
      browser = conn.browser;
      page = await browser.newPage();

      await goto(page, args.url, { timeout: 60000 });
      // Ensure tweet detail loads
      await page.waitForSelector('[data-testid="tweet"]', { timeout: 25000 }).catch(() => {});
      await sleep(2500);

      // Expand metrics section if needed by scrolling a bit
      await page.evaluate(() => window.scrollBy(0, 500)).catch(() => {});
      await sleep(1500);

      const raw = await page.evaluate(() => {
        // try a few likely containers
        const candidates = [];
        const metric = document.querySelector('[data-testid="app-text-transition-container"]');
        if (metric) candidates.push(metric.innerText);
        const article = document.querySelector('article');
        if (article) candidates.push(article.innerText);
        // also try looking for elements that contain the word 'Views' or '次观看'
        const els = Array.from(document.querySelectorAll('div,span'));
        for (const el of els.slice(0, 200)) {
          try {
            const t = (el.innerText || '').trim();
            if (t && /Views|次观看|观看/i.test(t)) candidates.push(t);
          } catch (e) {}
        }
        candidates.push(document.body.innerText);
        return candidates.filter(Boolean).join('\n----\n');
      });

      const views = parseViewsFromText(raw);

      console.log(JSON.stringify({ ok: views !== null, url: args.url, views: views, raw: views !== null ? null : raw.slice(0, 2000) }));

      try { await page.close(); } catch (e) {}
      try { browser.disconnect(); } catch (e) {}
      process.exit(0);
    } catch (e) {
      lastError = e;
      try { if (page) await page.close(); } catch (ex) {}
      try { if (browser && browser.disconnect) browser.disconnect(); } catch (ex) {}
      // transient errors: retry
      const msg = String(e && e.message ? e.message : e);
      if (/timeout|ECONNRESET|EPIPE|Target closed|Protocol error|connect ECONNREFUSED/i.test(msg)) {
        if (attempt < MAX_TRIES) {
          await new Promise(r => setTimeout(r, backoff));
          continue;
        }
      }
      console.log(JSON.stringify({ ok: false, url: args.url, error: msg }));
      process.exit(1);
    }
  }

  console.log(JSON.stringify({ ok: false, url: args.url, error: String(lastError || 'unknown') }));
  process.exit(1);
})();
