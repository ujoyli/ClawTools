#!/usr/bin/env node
// Usage: NODE_PATH=/tmp/node_modules node post-tweet.js <text> [--image path] [--port 18802] [--account @handle] [--dry-run]

const { connect, goto, typeIntoComposer, clickSend, attachMedia, attachImages, verifyAccount, dryRunScreenshot, cleanup, DEFAULT_PORT } = require('./lib/cdp-utils');
const { parseArgs } = require('./lib/args');
const { spawnSync } = require('child_process');
const path = require('path');

function isVideoFile(p) {
  return /\.(mp4|mov|m4v|webm)$/i.test(p || '');
}

function tryApiVideoFallback(text, media) {
  const videos = (media || []).filter(isVideoFile);
  if (videos.length === 0) return { ok: false, reason: 'no_video' };
  if (videos.length > 1) return { ok: false, reason: 'multi_video_not_supported' };

  const script = path.resolve(__dirname, '../../twitter-post/scripts/video_post.js');
  const videoPath = videos[0];

  const r = spawnSync('node', [script, videoPath, text], {
    encoding: 'utf8',
    env: process.env,
    timeout: 180000,
  });

  const out = (r.stdout || '').trim();
  let parsed = null;
  try { parsed = out ? JSON.parse(out) : null; } catch (_) {}

  if (r.status === 0 && parsed && parsed.ok) {
    return { ok: true, url: parsed.url || null, id: parsed.id || null };
  }

  return {
    ok: false,
    reason: 'api_failed',
    detail: (parsed && parsed.error) || (r.stderr || out || `exit_${r.status}`),
  };
}

const args = parseArgs(process.argv, {
  positional: ['text'],
  flags: { image: 'string[]', media: 'string[]', port: 'number', account: 'string', 'dry-run': 'boolean' },
  defaults: { text: '', image: [], media: [], port: DEFAULT_PORT, account: '', 'dry-run': false },
});

if (!args.text) {
  console.error('Usage: node post-tweet.js "tweet text" [--image /path] [--port 18802] [--account @handle] [--dry-run]');
  process.exit(1);
}

(async () => {
  const media = [...(args.media || []), ...(args.image || [])];
  const hasVideo = media.some(isVideoFile);
  const videos = media.filter(isVideoFile);

  // Try API with multiple retries for video tweets (503 is often temporary)
  if (hasVideo && !args['dry-run']) {
    console.log('Video detected, trying API upload (with retries)...');
    let apiSuccess = false;
    for (let retry = 0; retry < 5; retry++) {
      if (retry > 0) {
        console.log(`API retry ${retry}/5, waiting 10s...`);
        await new Promise(r => setTimeout(r, 10000));
      }
      const fb = tryApiVideoFallback(args.text, media);
      if (fb.ok) {
        console.log(`OK: Tweet posted via API${fb.url ? ` (${fb.url})` : ''}`);
        process.exit(0);
      }
      const detail = fb.detail || '';
      if (!detail.includes('503') && !detail.includes('Service Unavailable')) {
        console.log('API error not retriable: ' + detail.slice(0,100));
        break;
      }
    }
    console.log('All API retries failed, trying CDP...');
    // Continue to CDP below
  }

  // All tweets go through CDP (including video fallback)
  const { browser, newPage } = await connect(args.port);
  const page = await newPage();

  try {
    await goto(page, 'https://x.com/home');
    await verifyAccount(page, args.account || null);

    await goto(page, 'https://x.com/compose/post');
    await typeIntoComposer(page, args.text);

    // Attach media (images or videos via CDP)
    if (media.length > 0) {
      console.log('Attaching media via CDP...');
      await attachMedia(page, media);
      console.log('Media attached successfully');
    }

    if (args['dry-run']) {
      await dryRunScreenshot(page, 'post-tweet');
      console.log('DRY RUN: Tweet composed but not sent.');
      browser.disconnect();
      return;
    }

    await clickSend(page);
    console.log('OK: Tweet posted');
  } catch (e) {
    console.error('FAIL: ' + e.message);
    process.exit(1);
  } finally {
    if (!args['dry-run']) await cleanup(page, browser);
  }
})();
