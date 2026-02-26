#!/usr/bin/env python3.12
"""Fetch Douyin hot keywords (not videos) and output a tweet text.

Rationale: Automatically re-uploading arbitrary trending Douyin videos is high copyright risk.
This script instead pulls trending *hot words* and composes a text tweet with a search link.

Outputs a single line tweet text to stdout.
"""

import asyncio
import random
import sys
import urllib.parse

# DouK-Downloader codebase path
REPO = "/root/.openclaw/workspace/tmp_tiktokdownloader"
if REPO not in sys.path:
    sys.path.insert(0, REPO)


async def main():
    from src.interface.hot import Hot
    from src.testers import Params

    import contextlib
    import os

    # Params/Hot may print verbose debug. Silence stdout during fetch.
    with open(os.devnull, "w") as devnull, contextlib.redirect_stdout(devnull):
        async with Params() as params:
            hot = Hot(params)
            t, boards = await hot.run()

    # boards is list of tuples: (index, word_list)
    # pick Douyin hot榜 (board_params[0])
    word_list = None
    for idx, words in boards:
        if idx == 0:
            word_list = words
            break

    if not word_list:
        print("抖音热榜更新中，我先去喝口水，晚点再来。", flush=True)
        return

    # word item keys are site-dependent; try common ones
    def get_word(item: dict) -> str:
        for k in ("word", "keyword", "sentence", "title", "query"):
            v = item.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
        # fallback: first string value
        for v in item.values():
            if isinstance(v, str) and v.strip():
                return v.strip()
        return ""

    blocked = [
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

    top = ""
    for item in word_list[:20]:
        w = get_word(item)
        if not w:
            continue
        if any(b in w for b in blocked):
            continue
        top = w
        break

    if not top:
        print("热榜里全是敏感词，我先不自动发了。", flush=True)
        return

    link = "https://www.douyin.com/search/" + urllib.parse.quote(top)

    hooks = [
        "别问我怎么又刷到了，反正现在全网都在看：{w}",
        "今天的抖音热榜第一名：{w}（你看过了吗）",
        "热榜第一又离谱了：{w}",
        "抖音热榜刷新：{w} 这条不看真的亏",
    ]

    hook = random.choice(hooks).format(w=top)
    text = f"{hook}\n{link}\n#抖音热榜 #热点"

    # keep under 280 weighted chars; be conservative
    if len(text) > 240:
        text = f"抖音热榜：{top}\n{link}\n#抖音热榜"

    print(text, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
