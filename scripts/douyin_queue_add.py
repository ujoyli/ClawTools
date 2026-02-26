#!/usr/bin/env python3
"""Add selected candidates (by rank) into a local posting queue.

Reads candidates from:
  /root/.openclaw/workspace/data/douyin_candidates.txt (human)
  /root/.openclaw/workspace/data/douyin_candidates.json (machine)

Queue file:
  /root/.openclaw/workspace/data/douyin_video_queue.json

Usage:
  python scripts/douyin_queue_add.py 1 7 8
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime

CAND_JSON = "/root/.openclaw/workspace/data/douyin_candidates.json"
QUEUE_JSON = "/root/.openclaw/workspace/data/douyin_video_queue.json"


def load_json(path: str, default):
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: str, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: douyin_queue_add.py <rank> [rank...]", file=sys.stderr)
        return 2

    ranks = []
    for a in argv[1:]:
        try:
            ranks.append(int(a))
        except ValueError:
            print(f"Invalid rank: {a}", file=sys.stderr)
            return 2

    cand = load_json(CAND_JSON, {"candidates": []})
    cands = cand.get("candidates") or []
    rank_map = {c.get("rank"): c for c in cands if isinstance(c, dict)}

    q = load_json(QUEUE_JSON, {"queue": []})
    queue = q.get("queue") or []

    existing_urls = {item.get("url") for item in queue if isinstance(item, dict)}

    added = []
    for r in ranks:
        c = rank_map.get(r)
        if not c:
            continue
        url = c.get("url")
        title = (c.get("title") or "").strip()
        if not url or not title:
            continue
        if url in existing_urls:
            continue
        item = {
            "added_at": datetime.now().isoformat(),
            "rank": r,
            "title": title,
            "url": url,
            "status": "pending",
            "tweet_url": None,
        }
        queue.append(item)
        existing_urls.add(url)
        added.append(item)

    q["queue"] = queue
    save_json(QUEUE_JSON, q)

    print(f"queued: {len(added)}")
    for it in added:
        print(f"- {it['rank']}. {it['title']} {it['url']}")

    if len(added) != len(ranks):
        missing = [r for r in ranks if r not in rank_map]
        if missing:
            print(f"missing ranks (not in candidates.json): {missing}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
