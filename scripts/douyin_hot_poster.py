#!/usr/bin/env python
"""Generate a simple poster image for a hot topic (no copyrighted assets).

Usage:
  python scripts/douyin_hot_poster.py "topic text" /path/to/out.png

Writes a 1080x1080 PNG with title + timestamp + hashtag.
"""

from __future__ import annotations

import datetime as dt
import os
import sys
from textwrap import wrap

from PIL import Image, ImageDraw, ImageFont


def load_font(size: int) -> ImageFont.FreeTypeFont:
    # Prefer Noto/DejaVu if available
    candidates = [
        "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/google-noto-cjk/NotoSansCJKsc-Regular.otf",
        "/usr/share/fonts/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def main():
    if len(sys.argv) < 3:
        print("Usage: douyin_hot_poster.py <topic> <out.png>", file=sys.stderr)
        sys.exit(2)

    topic = sys.argv[1].strip()
    out = sys.argv[2]

    W = H = 1080
    bg = Image.new("RGB", (W, H), (12, 14, 18))
    d = ImageDraw.Draw(bg)

    # Accent bar
    d.rounded_rectangle((60, 80, 180, 980), radius=24, fill=(255, 77, 79))

    title_font = load_font(64)
    body_font = load_font(52)
    small_font = load_font(34)

    # Header
    d.text((230, 90), "抖音热榜", fill=(240, 240, 245), font=title_font)

    # Topic wrapped
    lines = wrap(topic, width=14)[:6]
    y = 220
    for i, line in enumerate(lines):
        d.text((230, y), line, fill=(255, 255, 255), font=body_font)
        y += 84

    ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    d.text((230, 930), f"更新: {ts}", fill=(170, 175, 185), font=small_font)
    d.text((230, 980), "#热点 #抖音热榜", fill=(120, 200, 255), font=small_font)

    bg.save(out, "PNG")


if __name__ == "__main__":
    main()
