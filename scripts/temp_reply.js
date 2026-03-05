#!/usr/bin/env node
// Reply to a viral tweet using cookies from /root/cookie.json

const puppeteer = require('puppeteer-core');
const fs = require('fs');

const TWEET_URL = 'https://x.com/geekbb/status/2029366508863013149';
const REPLY_TEXT = 'IP 段污染这招太狠了，直接物理断网。搬瓦工成了重点监控对象，同协议非瓦工能活说明不是协议特征被封。这猫鼠游戏越来越卷了，今天能用的明天就挂，得随时准备Plan B🤔';
const COOKIES_FILE = '/root/cookie.json';
const CDP_PORT = '18802';

(async () => {
  console.log('Connecting to Chromium on port ' + CDP_PORT + '...');
  
  let browser;
  try {
    browser = await puppeteer.connect({
      browserWSEndpoint: `ws://localhost:${CDP_PORT}/devtools/browser/default`
    });
    console.log('Connected to browser');
  } catch (e) {
    console.error('FAIL: Cannot connect to Chromium:', e.message);
    process.exit(1);
  }

  const page = await browser.newPage();
  
  try {
    // Load cookies
    console.log('Loading cookies...');
    const cookies = JSON.parse(fs.readFileSync(COOKIES_FILE, 'utf8'));
    
    // Filter for x.com cookies and set them
    const xCookies = cookies.filter(c => c.domain.includes('x.com') || c.domain.includes('twitter'));
    console.log('Setting ' + xCookies.length + ' cookies...');
    
    // Normalize cookies for puppeteer
    const normalizedCookies = xCookies.map(c => ({
      name: c.name,
      value: c.value,
      domain: c.domain.startsWith('.') ? c.domain.slice(1) : c.domain,
      path: c.path || '/',
      secure: c.secure || false,
      httpOnly: c.httpOnly || false,
    }));
    
    await page.setCookie(...normalizedCookies);
    
    // Navigate to the tweet
    console.log('Navigating to tweet...');
    await page.goto(TWEET_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 3000));
    
    // Check if we're logged in
    const url = page.url();
    console.log('Current URL:', url);
    
    // Try to find and click the reply button
    console.log('Looking for reply button...');
    const replyBtn = await page.$('[data-testid="reply"]');
    if (!replyBtn) {
      console.error('FAIL: Reply button not found. May not be logged in.');
      await page.screenshot({ path: '/root/.openclaw/workspace/x-reply-debug.png', fullPage: true });
      console.log('Screenshot saved to x-reply-debug.png');
      process.exit(1);
    }
    
    await replyBtn.click();
    await new Promise(r => setTimeout(r, 1500));
    
    // Find the textarea and type the reply
    console.log('Typing reply...');
    const textarea = await page.$('[data-testid="tweetTextarea_0"]');
    if (!textarea) {
      console.error('FAIL: Textarea not found');
      process.exit(1);
    }
    
    await textarea.click();
    await new Promise(r => setTimeout(r, 500));
    
    // Type using keyboard
    await page.keyboard.type(REPLY_TEXT, { delay: 30 });
    await new Promise(r => setTimeout(r, 1000));
    
    // Find and click the send button
    console.log('Sending reply...');
    const sendBtn = await page.$('[data-testid="tweetButton"]') || await page.$('[data-testid="tweetButtonInline"]');
    if (!sendBtn) {
      console.error('FAIL: Send button not found');
      process.exit(1);
    }
    
    await sendBtn.click();
    await new Promise(r => setTimeout(r, 3000));
    
    console.log('SUCCESS: Reply sent!');
    
  } catch (e) {
    console.error('FAIL:', e.message);
    await page.screenshot({ path: '/root/.openclaw/workspace/x-reply-error.png', fullPage: true });
    console.log('Error screenshot saved to x-reply-error.png');
    process.exit(1);
  } finally {
    await page.close();
    browser.disconnect();
  }
})();
