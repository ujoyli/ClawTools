---
name: bilibili-cookie-download
description: Download Bilibili videos on a server using a local exported cookie JSON (Cookie-Editor format) to bypass HTTP 412 / anti-bot checks, then optionally transcode AV1->H.264 for X/Twitter uploads. Use when user asks to download B站/Bilibili videos (BV/av links) and mentions cookies.json/cookies file, HTTP 412, server IP blocked, or needs an mp4 suitable for Twitter.
---

# Bilibili download via cookie JSON

Use this skill when yt-dlp fails on Bilibili with HTTP 412 on server IPs. The fix is to use the user's **local** exported cookie JSON to authenticate.

## Inputs (ask user for paths; do not ask them to paste cookies)

- Cookie JSON path (Cookie-Editor export JSON array), e.g. `~/bilibili_cookies.json`
- Bilibili URL, e.g. `https://www.bilibili.com/video/BV.../`

## Quick commands

### 1) Download as MP4 using cookies

```bash
python3 /root/.openclaw/workspace/skills/bilibili-cookie-download/scripts/cookie_json_to_netscape.py \
  --in /root/bilibili_cookies.json \
  --out /root/.openclaw/workspace/tmp/bili/bilibili_cookies.txt

yt-dlp \
  --cookies /root/.openclaw/workspace/tmp/bili/bilibili_cookies.txt \
  -f 'bv*+ba/b' --merge-output-format mp4 \
  -o '/root/.openclaw/workspace/tmp/bili/%(title).200s [%(id)s].%(ext)s' \
  'https://www.bilibili.com/video/BV18MfPB6EUC/'
```

### 2) If the resulting mp4 is AV1 and you need H.264 (e.g., X/Twitter upload)

This host ffmpeg may not include libx264. Use Docker ffmpeg to transcode:

```bash
bash /root/.openclaw/workspace/skills/bilibili-cookie-download/scripts/transcode_to_h264_docker.sh \
  '/root/.openclaw/workspace/tmp/bili/<input>.mp4' \
  '/root/.openclaw/workspace/tmp/bili/<output>-x264.mp4'
```

## Notes / Safety

- Treat cookie files as secrets. Never post them back to chat.
- Prefer using a secondary Bilibili account cookie if possible.
- Keep generated cookies.txt `chmod 600`.
