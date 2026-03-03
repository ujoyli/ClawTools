#!/usr/bin/env python3.12
"""Generate a clean square poster for XHS (no platform branding).

Usage:
  python scripts/xhs_poster.py --title "..." --subtitle "..." --out /path/out.png

No copyrighted assets. Simple typography only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
from textwrap import wrap

from PIL import Image, ImageDraw, ImageFont


def load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/google-noto-sans-cjk/NotoSansCJK-Regular.ttc",
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    title = args.title.strip()
    subtitle = args.subtitle.strip()

    W = H = 1080
    bg = Image.new("RGB", (W, H), (248, 248, 250))
    d = ImageDraw.Draw(bg)

    # accent
    d.rounded_rectangle((70, 90, 130, 990), radius=28, fill=(20, 120, 255))

    h_font = load_font(44)
    t_font = load_font(72)
    b_font = load_font(46)
    s_font = load_font(34)

    d.text((170, 90), "今日话题", fill=(30, 30, 35), font=h_font)

    # Title wrap
    lines = wrap(title, width=12)[:5]
    y = 220
    for line in lines:
        d.text((170, y), line, fill=(10, 10, 12), font=t_font)
        y += 100

    if subtitle:
        d.rounded_rectangle((170, y + 20, 1000, y + 20 + 140), radius=28, outline=(210, 210, 215), width=3)
        sub_lines = wrap(subtitle, width=18)[:2]
        yy = y + 45
        for line in sub_lines:
            d.text((200, yy), line, fill=(70, 70, 80), font=b_font)
            yy += 62

    ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    d.text((170, 1000), f"更新 {ts}", fill=(130, 130, 140), font=s_font)

    bg.save(args.out, "PNG")


if __name__ == "__main__":
    main()
