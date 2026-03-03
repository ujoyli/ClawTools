#!/usr/bin/env python3
"""
Scrape sopilot.net/zh/hot-tweets via agent-browser, save hot targets.
"""
import json, re, sys, os, time, argparse, subprocess, tempfile

REPLIED_PATH = "/root/.openclaw/workspace/data/x_replied_targets.json"
DEDUP_WINDOW = 72 * 3600
OUT_PATH = "/root/.openclaw/workspace/data/sopilot_hot_targets.json"


def parse_view_count(s: str) -> int:
    s = s.replace(",", "").strip()
    m = re.match(r"([\d.]+)\s*万", s)
    if m: return int(float(m.group(1)) * 10000)
    m = re.match(r"([\d.]+)\s*[kK]", s)
    if m: return int(float(m.group(1)) * 1000)
    try: return int(float(s))
    except: return 0


def get_replied_ids() -> set:
    try:
        obj = json.load(open(REPLIED_PATH, "r", encoding="utf-8"))
        replied = obj.get("replied", {})
        now = int(time.time())
        return {k for k, v in replied.items() if isinstance(v, int) and now - v < DEDUP_WINDOW}
    except:
        return set()


def scrape():
    tmp = tempfile.mktemp(suffix=".json")
    js = f'''(function(){{
const main = document.querySelector("main");
if (!main) return;
const tweetLinks = [...main.querySelectorAll("a[href*=tweetId]")];
const uniqueIds = [...new Set(tweetLinks.map(a => {{const m=a.href.match(/tweetId=(\\d+)/);return m?m[1]:null}}).filter(Boolean))];
const text = main.innerText;
const blocks = text.split(/(?=[\\d.]+[万kK]?粉\\n)/);
const results = [];
let idIdx = 0;
for (const block of blocks) {{
  const hm = block.match(/@(\\w+)/);
  if (!hm) continue;
  const handle = hm[1];
  const tm = block.match(/前发布\\n\\n([\\s\\S]*?)(?:\\n\\d{{1,6}}\\n)/);
  const tweetText = tm ? tm[1].trim().substring(0,500) : "";
  const pm = block.match(/起爆概率\\n(\\d+)%/);
  const prob = pm ? parseInt(pm[1]) : 0;
  const vm = block.match(/预测浏览量\\n([\\d,.]+[万kK]?)/);
  const pv = vm ? vm[1] : "0";
  const fm = block.match(/([\\d.]+[万kK]?)粉/);
  const followers = fm ? fm[1] : "0";
  const nm = block.match(/粉\\n(.+?)\\n@/);
  const name = nm ? nm[1].trim() : handle;
  const em = block.match(/预计可获得\\s*([\\d,.]+[万kK]?)\\s*次曝光/);
  const exposure = em ? em[1] : "0";
  const tid = idIdx < uniqueIds.length ? uniqueIds[idIdx] : null;
  idIdx++;
  results.push({{handle,name,followers,tweetText,prob,predictedViews:pv,exposure,tweetId:tid,url:tid?"https://x.com/"+handle+"/status/"+tid:null}});
}}
// Write to window for extraction
window.__sopilot_data = results;
}})()'''

    # Ensure page loaded
    subprocess.run(["agent-browser", "open", "https://sopilot.net/zh/hot-tweets"],
                   capture_output=True, text=True, timeout=20)
    time.sleep(5)

    # Run extraction
    subprocess.run(["agent-browser", "eval", js], capture_output=True, text=True, timeout=15)

    # Read data back via a file write approach
    write_js = f'JSON.stringify(window.__sopilot_data || [])'
    r = subprocess.run(["agent-browser", "eval", write_js], capture_output=True, text=True, timeout=10)
    raw = (r.stdout or '').strip()

    if not raw:
        return []

    # Remove outer quotes from agent-browser
    if raw.startswith('"') and raw.endswith('"'):
        try:
            raw = json.loads(raw)  # unescape quoted JSON string
        except Exception:
            return []

    if isinstance(raw, str):
        # best-effort extract first JSON array fragment
        m = re.search(r'\[.*\]', raw, re.S)
        if m:
            raw = m.group(0)
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, list) else []
        except Exception:
            return []

    return raw if isinstance(raw, list) else []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument("--min-views", type=int, default=10000)
    parser.add_argument("--min-prob", type=int, default=50)
    args = parser.parse_args()

    tweets = scrape()
    if not tweets:
        print("No tweets found", file=sys.stderr)
        sys.exit(1)

    print(f"Scraped {len(tweets)} tweets from sopilot")
    replied_ids = get_replied_ids()

    filtered = []
    for t in tweets:
        if t["prob"] < args.min_prob:
            continue
        pv = parse_view_count(t["predictedViews"])
        if pv < args.min_views:
            continue
        if not t.get("url"):
            continue
        tid = t.get("tweetId", "")
        if tid in replied_ids:
            continue
        t["predictedViewsNum"] = pv
        filtered.append(t)

    filtered.sort(key=lambda x: x["predictedViewsNum"], reverse=True)
    top = filtered[:args.top]

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump({"updated_at": int(time.time()), "targets": top}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    for i, t in enumerate(top):
        print(f"{i+1}. @{t['handle']} 起爆{t['prob']}% 预测{t['predictedViews']} | {t['url']}")
        print(f"   {t['tweetText'][:100]}")

    print(f"\nSaved {len(top)} targets to {OUT_PATH}")


if __name__ == "__main__":
    main()
