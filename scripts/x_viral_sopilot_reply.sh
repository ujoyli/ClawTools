#!/usr/bin/env bash
# Viral reply using sopilot hot tweets as target source
# 1) Refresh sopilot targets
# 2) Pick best unreplied target
# 3) Generate reply via agent
# 4) Post via CDP
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
export NODE_PATH=/tmp/node_modules

cd "$WORKDIR"

# Prevent overlap
exec 9>/tmp/x_viral_fast_reply.lock
flock -n 9 || exit 0

# Small jitter
python3 -c "import random,time;s=random.randint(0,30);print(f'jitter={s}s');time.sleep(s)"

# 1) Refresh sopilot targets
echo "Refreshing sopilot hot targets..."
python3 scripts/sopilot_hot_tweets.py --top 10 --min-prob 50 --min-views 10000 2>&1 || true

TARGETS_FILE="$WORKDIR/data/sopilot_hot_targets.json"
if [[ ! -f "$TARGETS_FILE" ]]; then
  echo "No sopilot targets available, falling back to old method"
  # Fallback to old find_one_viral_tweet.py
  exec bash scripts/x_viral_fast_reply_legacy.sh
fi

# 2) Pick first unreplied target
read -r TARGET_URL TWEET_TEXT <<< "$(python3 - <<'PY'
import json, os, re, time

targets = json.load(open("/root/.openclaw/workspace/data/sopilot_hot_targets.json"))
replied_path = "/root/.openclaw/workspace/data/x_replied_targets.json"
now = int(time.time())
window = 72 * 3600

try:
    replied = json.load(open(replied_path)).get("replied", {})
    replied = {k: v for k, v in replied.items() if isinstance(v, int) and now - v < window}
except:
    replied = {}

blacklist = ["whyyoutouzhele", "teacherli1", "liteacher", "lixiansheng"]

for t in targets.get("targets", []):
    tid = t.get("tweetId", "")
    url = (t.get("url", "") or "").lower()
    if any(b in url for b in blacklist):
        continue
    if tid and tid not in replied:
        text = t.get("tweetText", "").replace("\n", " ").strip()[:280]
        print(f"{t.get('url','')}\t{text}")
        # Mark as replied
        replied[tid] = now
        with open(replied_path, "w") as f:
            json.dump({"replied": replied}, f, ensure_ascii=False)
            f.write("\n")
        break
else:
    print("\t")
PY
)"

if [[ -z "$TARGET_URL" ]]; then
  echo "No unreplied targets available"
  exit 0
fi

export TARGET_URL TWEET_TEXT
echo "Target: $TARGET_URL"

# 3) Generate reply via agent
PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "" "$TWEET_TEXT")

AGENT_JSON=""
for i in 1 2 3; do
  set +e
  AGENT_JSON=$(openclaw agent --session-id x-fast-reply --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/tmp/x_agent_err.log)
  RC=$?
  set -e
  printf '%s' "$AGENT_JSON" > /tmp/x_agent_reply.json
  if [[ $RC -eq 0 && -n "$AGENT_JSON" ]]; then break; fi
  sleep 2
done

REPLY_TEXT=$(python3 - <<'PY'
import json
try:
    obj = json.load(open("/tmp/x_agent_reply.json"))
    if isinstance(obj, dict):
        payloads = obj.get("payloads", [])
        if payloads:
            text = (payloads[0].get("text") or "").strip()
            if text: print(text); raise SystemExit
        text = (obj.get("result", {}).get("payloads", [{}])[0].get("text") or "").strip()
        if text: print(text)
except: pass
PY
)
# normalize escaped newlines like "\\n" into real line breaks
REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"

if [[ -z "$REPLY_TEXT" ]]; then
  echo "Agent returned empty reply" >&2
  exit 1
fi

export REPLY_TEXT
echo "Reply: $REPLY_TEXT"

# 4) Post reply via CDP
NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407 | tee -a /tmp/x_fast_reply_post.log

# 5) Log
python3 - <<'PY'
import json, time, os
obj = {
    "ts": int(time.time()),
    "source": "sopilot",
    "target_url": os.environ.get("TARGET_URL", ""),
    "tweet_text": os.environ.get("TWEET_TEXT", "")[:280],
    "reply_text": os.environ.get("REPLY_TEXT", "")[:280]
}
with open("/root/.openclaw/workspace/data/x_reply_log.jsonl", "a") as f:
    f.write(json.dumps(obj, ensure_ascii=False) + "\n")
PY
