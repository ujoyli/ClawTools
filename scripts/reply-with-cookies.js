#!/usr/bin/env node
// Reply to a tweet using cookies from /root/cookie.json

const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

const TWEET_URL = 'https://x.com/global_bests/status/2028469121281561025';
const REPLY_TEXT = '女儿国到了，唐僧却不够分了！以前男多女少，现在女多男少。相亲角阿姨手里的简历比紧箍咒还厚，小伙子成了稀缺物种。这剧情反转得比电视剧还快，月老怕是要改 KPI 了😂';
const COOKIES_FILE = '/root/cookie.json';

(async () => {
  console.log('Connecting to Chromium on port 18802...');
  
  let browser;
  try {
    browser = await puppeteer.connect({
      browserURL: 'http://localhost:18802',
    });
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
    console.log(`Setting ${xCookies.length} cookies...`);
    
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
    
    // Check if we're logged in by looking for user avatar or home timeline
    const url = page.url();
    console.log('Current URL:', url);
    
    // Try to find and click the reply button
    console.log('Looking for reply button...');
    const replyBtn = await page.$('[data-testid="reply"]');
    if (!replyBtn) {
      console.error('FAIL: Reply button not found. May not be logged in.');
      // Save screenshot for debugging
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
