#!/usr/bin/env node
/**
 * Post a tweet with an image (native upload) using Twitter/X API.
 * Requires OAuth 1.0a user context.
 *
 * Env vars:
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
  console.log(JSON.stringify({ ok: false, error: 'Usage: node scripts/image_post.js <imagePath> <text>' }));
}

(async () => {
  const imagePath = process.argv[2];
  const text = process.argv.slice(3).join(' ');

  if (!imagePath || !text) {
    usage();
    process.exit(2);
  }

  const abs = path.resolve(imagePath);
  if (!fs.existsSync(abs)) {
    console.log(JSON.stringify({ ok: false, error: `Image not found: ${abs}` }));
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

    // v1.1 media upload
    const mediaId = await rw.v1.uploadMedia(abs); // autodetect

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
