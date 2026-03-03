#!/usr/bin/env node
// Usage: NODE_PATH=/tmp/node_modules node reply-tweet.js <tweet_url> <reply_text> [--image path] [--port 18802] [--account @handle] [--dry-run]

const { connect, goto, clickSend, attachMedia, attachImages, verifyAccount, dryRunScreenshot, cleanup, sleep, SELECTORS, DEFAULT_PORT } = require('./lib/cdp-utils');
const { parseArgs } = require('./lib/args');

const args = parseArgs(process.argv, {
  positional: ['url', 'text'],
  flags: { image: 'string[]', media: 'string[]', port: 'number', account: 'string', 'dry-run': 'boolean' },
  defaults: { url: '', text: '', image: [], media: [], port: DEFAULT_PORT, account: '', 'dry-run': false },
});

if (!args.url || !args.text) {
  console.error('Usage: node reply-tweet.js <tweet_url> "reply text" [--image /path] [--port 18802] [--account @handle] [--dry-run]');
  process.exit(1);
}

// Normalize escaped sequences so literal "\\n" becomes actual line breaks
if (typeof args.text === 'string' && args.text.includes('\\')) {
  args.text = args.text
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '\r')
    .replace(/\\t/g, '\t');
}

(async () => {
  const { browser, newPage } = await connect(args.port);
  const page = await newPage();

  try {
    await goto(page, args.url);
    await verifyAccount(page, args.account || null);

    // Click reply button and wait for editor
    const replyBtn = await page.$(SELECTORS.replyButton);
    if (!replyBtn) throw new Error('Reply button not found on this tweet');
    await replyBtn.click();

    const editor = await page.waitForSelector(SELECTORS.tweetTextarea, { timeout: 10000 })
      .catch(() => null);
    if (!editor) throw new Error('Reply editor did not appear');
    await editor.click();
    await sleep(300);
    await page.keyboard.type(args.text, { delay: 25 });
    await sleep(500);

    const media = [...(args.media || []), ...(args.image || [])];
    if (media.length > 0) {
      await attachMedia(page, media);
    }

    if (args['dry-run']) {
      await dryRunScreenshot(page, 'reply-tweet');
      console.log('DRY RUN: Reply composed but not sent.');
      browser.disconnect();
      return;
    }

    // Skip media wait for text-only replies
    await (async () => {
      await sleep(2000);
      const btn = await page.$(SELECTORS.tweetButton) || await page.$(SELECTORS.tweetButtonInline);
      if (!btn) throw new Error('Send button not found');
      await btn.click();
      await sleep(3000);
    })();
    console.log('OK: Reply sent to ' + args.url);
  } catch (e) {
    console.error('FAIL: ' + e.message);
    process.exit(1);
  } finally {
    if (!args['dry-run']) await cleanup(page, browser);
  }
})();
