---
name: twitter-post
description: Post tweets to Twitter/X via the official API v2 (OAuth 1.0a). Use when the user asks to tweet, post to Twitter/X, send a thread, reply to a tweet, or quote tweet. Supports single tweets, threads, replies, and quote tweets with automatic character weight validation.
---

# Twitter Post

Post tweets via the official Twitter/X API v2 using OAuth 1.0a authentication.

## Prerequisites

Four environment variables must be set. Obtain them from [developer.x.com](https://developer.x.com):

```
TWITTER_CONSUMER_KEY=<API Key>
TWITTER_CONSUMER_SECRET=<API Key Secret>
TWITTER_ACCESS_TOKEN=<Access Token>
TWITTER_ACCESS_TOKEN_SECRET=<Access Token Secret>
```

Optional:
- `HTTPS_PROXY` — HTTP proxy URL (e.g. `http://127.0.0.1:7897`) for regions that need it
- `TWITTER_DRY_RUN=1` — validate and print without posting

## Setup

Store credentials as env vars. Recommended: add to the OpenClaw instance config, a locked-down env file, or export in shell profile.

**Never hardcode keys in SKILL.md or scripts. Never echo keys back into chat.**

### Suggested env file location

A practical pattern is to keep credentials at:
- `/root/.config/x-twitter/.env`

with permissions like `600`.

Expected keys inside:
- `TWITTER_CONSUMER_KEY`
- `TWITTER_CONSUMER_SECRET`
- `TWITTER_ACCESS_TOKEN`
- `TWITTER_ACCESS_TOKEN_SECRET`

Optional:
- `TWITTER_BEARER_TOKEN` (not required for posting with OAuth 1.0a)

If the user hasn't set up OAuth yet, guide them:

1. Go to [developer.x.com](https://developer.x.com) → Dashboard → Create App
2. Set **App permissions** to **Read and Write**
3. Go to **Keys and tokens** tab
4. Copy API Key, API Key Secret
5. Generate Access Token and Access Token Secret (ensure Read+Write scope)
6. If the portal only shows Read, use PIN-based OAuth flow:
   - Call `POST /oauth/request_token` with `oauth_callback=oob`
   - User opens `https://api.twitter.com/oauth/authorize?oauth_token=<token>`
   - User provides the PIN code
   - Call `POST /oauth/access_token` with the PIN as `oauth_verifier`

## Usage

All commands via `exec`.

Scripts (relative to this skill directory):
- `scripts/tweet.js` — text tweets (single/reply/quote/thread)
- `scripts/image_post.js` — upload an image and post a tweet with media
- `scripts/video_post.js` — upload a video and post a tweet with media

### Load env vars (recommended)

If secrets are stored in an env file (example: `/root/.config/x-twitter/.env`), load them **without printing**:

```bash
set -a
source /root/.config/x-twitter/.env
set +a
```

Then run the scripts normally.

### Single tweet

```bash
node scripts/tweet.js "Your tweet content here"
```

### Reply to a tweet

```bash
node scripts/tweet.js --reply-to 1234567890 "Reply text"
```

### Quote tweet

```bash
node scripts/tweet.js --quote 1234567890 "Your commentary"
```

### Thread (multiple tweets)

```bash
node scripts/tweet.js --thread "First tweet" "Second tweet" "Third tweet"
```

### Tweet with image

```bash
node scripts/image_post.js /absolute/path/to/image.png "Your tweet text here"
```

### Tweet with video

```bash
node scripts/video_post.js /absolute/path/to/video.mp4 "Your tweet text here"
```

Notes:
- Media upload uses Twitter API v1.1 under the hood, then posts the tweet via v2.
- Prefer an absolute file path.
- If upload fails, check file size/duration and that your app/user has the right permissions.

### Output

JSON to stdout:

```json
{"ok":true,"id":"123456789","url":"https://x.com/i/status/123456789","remaining":"99","limit":"100"}
```

On error: `{"ok":false,"error":"..."}`

## Character Limits

- Max 280 weighted characters per tweet
- CJK characters (Chinese/Japanese/Korean) count as **2** each
- URLs count as **23** each regardless of length
- Script auto-validates before posting; rejects if over limit

## Rate Limits

- **100 tweets / 15 min** per user (OAuth 1.0a)
- **3,000 tweets / month** on Basic plan ($200/mo)
- Check `remaining` field in output to monitor quota

## Tips

- For content from Notion/database: fetch the text first, then pipe to `tweet.js`
- For cron-based auto-posting: use `exec` with env vars set, parse JSON output to confirm success
- Thread mode posts sequentially; each tweet auto-replies to the previous one
- Combine `--thread` with `--reply-to` to attach a thread under an existing tweet
