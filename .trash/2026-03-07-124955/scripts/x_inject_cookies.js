#!/usr/bin/env node
// Inject /root/cookie.json into the running CDP Chromium and verify login
const fs = require('fs');
const puppeteer = require('puppeteer-core');
const PORT = parseInt(process.env.CDP_PORT || '18802');

(async () => {
  const browser = await puppeteer.connect({ browserURL: `http://localhost:${PORT}` });
  const pages = await browser.pages();
  const page = pages[0] || await browser.newPage();

  // Navigate to x.com first (cookies need matching domain context)
  await page.goto('https://x.com', { waitUntil: 'domcontentloaded', timeout: 20000 });

  const raw = JSON.parse(fs.readFileSync('/root/cookie.json', 'utf8'));
  for (const c of raw) {
    await page.setCookie({
      name: c.name,
      value: c.value,
      domain: c.domain,
      path: c.path || '/',
      httpOnly: !!c.httpOnly,
      secure: !!c.secure,
      ...(c.expirationDate ? { expires: Math.floor(c.expirationDate) } : {}),
    });
  }
  console.log(`Injected ${raw.length} cookies`);

  // Reload to pick up cookies
  await page.goto('https://x.com/home', { waitUntil: 'networkidle2', timeout: 30000 });
  const url = page.url();
  const loggedIn = !url.includes('login');
  console.log('URL:', url);
  console.log('Logged in:', loggedIn);

  if (loggedIn) {
    const handle = await page.evaluate(() => {
      const btn = document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]');
      const m = btn?.textContent?.match(/@\w+/);
      return m ? m[0] : null;
    }).catch(() => null);
    console.log('Handle:', handle);
  }

  await page.close();
  browser.disconnect();

  if (!loggedIn) {
    console.error('FAIL: Cookie injection did not result in login');
    process.exit(1);
  }
})().catch(e => { console.error(e); process.exit(1); });
