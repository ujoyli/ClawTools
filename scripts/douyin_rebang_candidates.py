#!/usr/bin/env python
"""Build a daily list of Douyin video candidates from rebang.today.

Source page:
  https://rebang.today/?tab=douyin

Mechanism:
- Use local BrowserWing executor HTTP API (127.0.0.1:18080)
- Navigate to rebang page
- Evaluate JS to extract douyin.com/video/ links + best title text
- Write candidates list to:
  - /root/.openclaw/workspace/data/douyin_candidates.txt
  - /root/.openclaw/workspace/data/douyin_candidates.json

This does NOT download or post videos.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime

import httpx

BW = os.environ.get("BROWSERWING_URL", "http://127.0.0.1:18080")
OUT_DIR = "/root/.openclaw/workspace/data"
OUT_TXT = os.path.join(OUT_DIR, "douyin_candidates.txt")
OUT_JSON = os.path.join(OUT_DIR, "douyin_candidates.json")


def bw_post(client: httpx.Client, endpoint: str, payload: dict, timeout: float = 60.0):
    r = client.post(f"{BW}{endpoint}", json=payload, timeout=timeout)
    r.raise_for_status()
    obj = r.json()
    if not obj.get("success", False):
        raise RuntimeError(f"BrowserWing error at {endpoint}: {obj}")
    return obj


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    with httpx.Client(headers={"Content-Type": "application/json"}) as client:
        # Health check
        try:
            h = client.get(f"{BW}/health", timeout=5.0)
            h.raise_for_status()
        except Exception as e:
            raise RuntimeError(f"BrowserWing not reachable at {BW}: {e}")

        # Navigate
        bw_post(
            client,
            "/api/v1/executor/navigate",
            {
                "url": "https://rebang.today/?tab=douyin",
                "wait_until": "domcontentloaded",
                "timeout": 60,
            },
            timeout=120.0,
        )

        # Wait for dynamic content to load
        bw_post(
            client,
            "/api/v1/executor/wait",
            {"identifier": "a[href*=\"douyin.com/video/\"]", "state": "visible", "timeout": 30},
            timeout=40.0,
        )

        # Extract douyin video links + titles
        # Each entry often appears twice (duration + title). Pick longest non-duration text per href.
        script = r"""() => {
  const out = [];
  const isDuration = (s) => /^\d{2}:\d{2}$/.test(s);
  const map = new Map();
  document.querySelectorAll('a[href*="douyin.com/video/"]').forEach(a => {
    const href = a.href;
    const txt = (a.textContent || '').trim().replace(/\s+/g,' ');
    if (!href) return;
    if (!map.has(href)) map.set(href, {href, title: ''});
    if (txt && !isDuration(txt) && txt.length > map.get(href).title.length) {
      map.get(href).title = txt;
    }
  });
  Array.from(map.values()).forEach(x => {
    if (x.title && x.href) out.push(x);
  });
  // Keep deterministic order: as they appear in DOM
  const seen = new Set();
  const ordered = [];
  document.querySelectorAll('a[href*="douyin.com/video/"]').forEach(a => {
    const href = a.href;
    if (seen.has(href)) return;
    seen.add(href);
    const found = out.find(o => o.href === href);
    if (found) ordered.push(found);
  });
  return ordered.slice(0, 30);
}"""

        res = bw_post(
            client,
            "/api/v1/executor/evaluate",
            {"script": script},
            timeout=60.0,
        )
        # BrowserWing returns { data: { result: <value> } }
        items = res.get("data", {}).get("result", [])

    # Build candidates
    candidates = []
    for i, it in enumerate(items, start=1):
        if not isinstance(it, dict):
            continue
        url = it.get("href")
        title = (it.get("title") or "").strip()
        if not url or not title:
            continue
        candidates.append({"rank": len(candidates) + 1, "title": title, "url": url})
        if len(candidates) >= 12:
            break

    payload = {"generated_at": datetime.now().isoformat(), "source": "rebang.today/douyin", "candidates": candidates}
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = [
        f"候选生成时间: {payload['generated_at']}",
        "来源: https://rebang.today/?tab=douyin",
        "回复数字选择 3 条（例如：1 3 7）：",
        "",
    ]
    for c in candidates:
        lines.append(f"{c['rank']}. {c['title']}  {c['url']}")
    lines.append("")

    with open(OUT_TXT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
