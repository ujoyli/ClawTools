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

# Ensure cookie and CDP are ready
source "$WORKDIR/scripts/ensure_x_cookie.sh" > /tmp/ensure_cookie_fast_reply.log 2>&1 || true
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_fast_reply.log 2>&1 || true

# Prevent overlap
exec 9>/tmp/x_viral_fast_reply.lock
flock -n 9 || exit 0

# Small jitter
python3 -c "import random,time;s=random.randint(0,30);print(f'jitter={s}s');time.sleep(s)"

TARGETS_FILE="$WORKDIR/data/sopilot_hot_targets.json"
TARGET_URL=""
TWEET_TEXT=""
MAX_PICK_TRIES=4

# 1) Refresh+pick with retries
for pick_try in $(seq 1 $MAX_PICK_TRIES); do
  echo "Refreshing sopilot hot targets... (try $pick_try/$MAX_PICK_TRIES)"
  REFRESH_OUT=$(python3 scripts/sopilot_hot_tweets.py --top 10 --min-prob 50 --min-views 10000 2>&1 || true)
  echo "$REFRESH_OUT"

  if [[ ! -f "$TARGETS_FILE" ]]; then
    echo "No sopilot targets available in this try"
    sleep 5
    continue
  fi

  # 2) Pick first unreplied qualified target
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

blacklist_path = "/root/.openclaw/workspace/data/blacklist.txt"
try:
    blacklist = [line.strip() for line in open(blacklist_path) if line.strip()]
except:
    blacklist = []

# Political keywords to filter
political = ['政治', '习近平', '共产党', '中共', '特朗普', '拜登', '美国大选', '两会', '中南海', '白宫', '普京', '俄罗斯', '乌克兰', '以色列', '哈马斯', '伊朗', '战争', '军队', '军方', '敏感', '封禁', '审查']
# Tech keywords (priority)
tech = ['AI', '人工智能', 'GPT', 'Claude', '编程', '代码', '软件', '开发', '技术', '科技', '互联网', '创业', '产品', '算法', '机器学习', '深度学习', '区块链', 'Web3', 'SaaS', 'API', 'GitHub', '开源']
# Society keywords
society = ['社会', '热点', '新闻', '八卦', '明星', '娱乐', '电影', '游戏', '体育', 'NBA', '足球', '篮球', '恋爱', '情感', '职场', '生活']

def topic_score(txt):
    tl = txt.lower()
    if any(k in tl for k in political):
        return -1000
    if any(k in tl for k in tech):
        return 100
    if any(k in tl for k in society):
        return 50
    return 0

best = None
for t in targets.get("targets", []):
    tid = t.get("tweetId", "")
    url = (t.get("url", "") or "").lower()
    if any(b in url for b in blacklist):
        continue

    # Hard rule: only reply to tweets within 2 hours
    age_h = float(t.get("age_h", 999))
    if age_h > 2:
        continue

    text = t.get("tweetText", "").replace("\n", " ").strip()
    if any(p in text.lower() for p in political):
        continue
    if tid and tid not in replied:
        ts = topic_score(text)
        if ts < 0:
            continue
        if best is None or ts > best[1]:
            best = (t, ts, text[:280])

if best:
    t, _, text = best
    print(f"{t.get('url','')}\t{text}")
    replied[t.get('tweetId','')] = now
    with open(replied_path, "w") as f:
        json.dump({"replied": replied}, f, ensure_ascii=False)
        f.write("\n")
else:
    print("\t")
PY
)"

  if [[ -n "$TARGET_URL" ]]; then
    echo "Found qualified target on try $pick_try"
    break
  fi

  echo "No qualified targets on try $pick_try, refreshing..."
  sleep 5
done

if [[ -z "$TARGET_URL" ]]; then
  echo "No unreplied qualified targets available after $MAX_PICK_TRIES tries"
  exit 75
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
POST_OUT=$(NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407 2>&1 | tee -a /tmp/x_fast_reply_post.log)

if ! echo "$POST_OUT" | grep -Eiq "(OK|posted|success|replied)"; then
  echo "Post may have failed: $POST_OUT" >&2
  exit 1
fi

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
