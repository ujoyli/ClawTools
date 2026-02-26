#!/usr/bin/env python
"""Generate a daily list of video candidates from Douyin hot words.

Workflow:
- Fetch Douyin hot word list (Hot board 0)
- Filter sensitive/blocked keywords
- For each word, run Douyin video search and pick the first aweme_id
- Save JSON candidates + a text summary file

This does NOT post anything.

Outputs:
- /root/.openclaw/workspace/data/douyin_candidates.json
- /root/.openclaw/workspace/data/douyin_candidates.txt
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import os
import sys
from datetime import datetime

REPO = "/root/.openclaw/workspace/tmp_tiktokdownloader"
if REPO not in sys.path:
    sys.path.insert(0, REPO)

OUT_DIR = "/root/.openclaw/workspace/data"
OUT_JSON = os.path.join(OUT_DIR, "douyin_candidates.json")
OUT_TXT = os.path.join(OUT_DIR, "douyin_candidates.txt")

BLOCKED = [
    "习近平",
    "李强",
    "普京",
    "拜登",
    "特朗普",
    "以色列",
    "哈马斯",
    "乌克兰",
    "俄罗斯",
    "台湾",
    "选举",
    "投票",
    "战争",
]


def get_word(item: dict) -> str:
    for k in ("word", "keyword", "sentence", "title", "query"):
        v = item.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    for v in item.values():
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def extract_aweme_id(search_item: dict) -> str:
    # Search channel=video usually returns items containing aweme_info
    aweme = search_item.get("aweme_info") or search_item.get("aweme") or {}
    for k in ("aweme_id", "awemeId", "id"):
        v = aweme.get(k) if isinstance(aweme, dict) else None
        if v:
            return str(v)
    # fallback: scan for plausible id
    for k, v in search_item.items():
        if k in ("aweme_id", "awemeId") and v:
            return str(v)
    return ""


async def main():
    from src.interface.hot import Hot
    from src.interface.search import Search
    from src.testers import Params

    os.makedirs(OUT_DIR, exist_ok=True)

    with open(os.devnull, "w") as devnull, contextlib.redirect_stdout(devnull):
        async with Params() as params:
            hot = Hot(params)
            t, boards = await hot.run()

            word_list = None
            for idx, words in boards:
                if idx == 0:
                    word_list = words
                    break

            if not word_list:
                payload = {"generated_at": datetime.now().isoformat(), "candidates": []}
                json.dump(payload, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
                open(OUT_TXT, "w", encoding="utf-8").write("热榜为空\n")
                return

            candidates = []
            seen_aweme = set()

            # Try top N words
            for item in word_list[:30]:
                w = get_word(item)
                if not w or any(b in w for b in BLOCKED):
                    continue

                s = Search(params, keyword=w, channel=1, pages=1, count=10)
                res = await s.run(single_page=True)
                if not res or not isinstance(res, list):
                    continue

                # res may contain nested lists; flatten one level
                flat = []
                for r in res:
                    if isinstance(r, list):
                        flat.extend(r)
                    else:
                        flat.append(r)

                aweme_id = ""
                for r in flat:
                    if not isinstance(r, dict):
                        continue
                    aweme_id = extract_aweme_id(r)
                    if aweme_id:
                        break

                if not aweme_id or aweme_id in seen_aweme:
                    continue
                seen_aweme.add(aweme_id)

                candidates.append(
                    {
                        "rank": len(candidates) + 1,
                        "keyword": w,
                        "aweme_id": aweme_id,
                        "url": f"https://www.douyin.com/video/{aweme_id}",
                    }
                )

                if len(candidates) >= 12:
                    break

    payload = {
        "generated_at": datetime.now().isoformat(),
        "candidates": candidates,
    }
    json.dump(payload, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    lines = [
        f"候选生成时间: {payload['generated_at']}",
        "从抖音热榜关键词→视频搜索得到的候选（回复数字选择 3 条，例如：1 3 7）：",
        "",
    ]
    for c in candidates:
        lines.append(f"{c['rank']}. {c['keyword']}  {c['url']}")
    lines.append("")
    open(OUT_TXT, "w", encoding="utf-8").write("\n".join(lines))


if __name__ == "__main__":
    asyncio.run(main())
