#!/usr/bin/env node
/**
 * Post a tweet with a video (native upload) using Twitter/X API.
 * Requires OAuth 1.0a user context.
 *
 * Env vars (compatible with twitter-post skill naming):
 *   TWITTER_CONSUMER_KEY
 *   TWITTER_CONSUMER_SECRET
 *   TWITTER_ACCESS_TOKEN
 *   TWITTER_ACCESS_TOKEN_SECRET
 */

const fs = require('fs');
const path = require('path');
const { TwitterApi } = require('twitter-api-v2');

function getEnv(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing ${name}`);
  return v;
}

function usage() {
  console.log(JSON.stringify({ ok: false, error: 'Usage: node scripts/video_post.js <videoPath> <text>' }));
}

(async () => {
  const videoPath = process.argv[2];
  const text = process.argv.slice(3).join(' ');

  if (!videoPath || !text) {
    usage();
    process.exit(2);
  }

  const abs = path.resolve(videoPath);
  if (!fs.existsSync(abs)) {
    console.log(JSON.stringify({ ok: false, error: `Video not found: ${abs}` }));
    process.exit(2);
  }

  try {
    const client = new TwitterApi({
      appKey: getEnv('TWITTER_CONSUMER_KEY'),
      appSecret: getEnv('TWITTER_CONSUMER_SECRET'),
      accessToken: getEnv('TWITTER_ACCESS_TOKEN'),
      accessSecret: getEnv('TWITTER_ACCESS_TOKEN_SECRET'),
    });

    const rw = client.readWrite;

    // Upload video via v1.1 (chunked upload handled by library)
    const mediaId = await rw.v1.uploadMedia(abs, { type: 'longmp4' });

    const resp = await rw.v2.tweet({
      text,
      media: { media_ids: [mediaId] },
    });

    const id = resp?.data?.id;
    const url = id ? `https://x.com/i/status/${id}` : null;

    console.log(JSON.stringify({ ok: true, id, url }));
  } catch (e) {
    const msg = e?.data ? JSON.stringify(e.data) : (e?.message || String(e));
    console.log(JSON.stringify({ ok: false, error: msg }));
    process.exit(1);
  }
})();
