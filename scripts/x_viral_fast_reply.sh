#!/usr/bin/env bash
# High frequency viral reply agent (randomized ~1–2 min)
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
export NODE_PATH=/tmp/node_modules

cd "$WORKDIR"
source tmp_tiktokdownloader/.venv/bin/activate

# Prevent overlap
exec 9>/tmp/x_viral_fast_reply.lock
flock -n 9 || exit 0

# Small jitter only (avoid bot-like exact intervals)
python3 - <<'PY'
import random, time
sleep_s = random.randint(0, 20)
print(f"jitter={sleep_s}s")
time.sleep(sleep_s)
PY

# 1) Find a target
echo "Finding target..."
python3 scripts/find_one_viral_tweet.py > /tmp/x_viral_run.log 2>&1 || true

TARGET_URL=$(grep "SUCCESS:" /tmp/x_viral_run.log | awk '{print $2}' || true)
if [[ -z "$TARGET_URL" ]]; then exit 0; fi
export TARGET_URL

# Dedupe: skip if already replied in last 24h
if ! python3 - <<'PY'
import json, os, re, time
path='/root/.openclaw/workspace/data/x_replied_targets.json'
url=os.environ.get('TARGET_URL','')
# extract status id
m=re.search(r'/status/(\d+)', url)
status=m.group(1) if m else url
now=int(time.time())
window=24*3600
obj={'replied':{}}
try:
    obj=json.load(open(path,'r',encoding='utf-8'))
except Exception:
    obj={'replied':{}}
replied=obj.get('replied',{}) if isinstance(obj,dict) else {}
# purge old
replied={k:v for k,v in replied.items() if isinstance(v,int) and now-v<window}
if status in replied:
    raise SystemExit(2)
# mark now (optimistic)
replied[status]=now
with open(path,'w',encoding='utf-8') as f:
    json.dump({'replied': replied}, f, ensure_ascii=False)
    f.write('\n')
PY
then
  DEDUP_CODE=$?
  if [[ "$DEDUP_CODE" == "2" ]]; then exit 0; fi
  exit "$DEDUP_CODE"
fi

TWEET_TEXT=$(python3 -c "import json; print(json.load(open('data/last_viral_target.json'))['text'])" 2>/dev/null || true)

export TARGET_URL TWEET_TEXT

# 2) Generate reply via OpenClaw agent (always)
PROMPT_FILE=/tmp/x_agent_prompt.txt
cat > "$PROMPT_FILE" <<EOF
你是一个擅长在 X(推特) 爆款推文下写高质量评论的账号运营。
写作风格：去 AI 味，像真人在评论区顺手丢一句。
要求：
- 简短、有态度（<= 180 字符）
- 如果原推文含中文就用中文回复；否则用英文
- 不要复读原文，不要“总结式/教科书式”
- 避免 AI 常见套话："很棒的分享"、"值得关注"、"深入探讨"、"让我们" 等
- 尽量给出一个具体点：一个反问/一个小结论/一个小补充（别空泛）
- 不要提到你是 AI
- 不要带链接

原推文内容：
${TWEET_TEXT}
EOF

AGENT_JSON=""
AGENT_ERR=""
for i in 1 2 3; do
  set +e
  AGENT_JSON=$(openclaw agent --session-id x-fast-reply --thinking minimal --timeout 120 --json --message "$(cat "$PROMPT_FILE")" 2> /tmp/x_agent_err.log)
  RC=$?
  set -e
  AGENT_ERR=$(cat /tmp/x_agent_err.log 2>/dev/null || true)
  printf '%s' "$AGENT_JSON" > /tmp/x_agent_reply.json
  if [[ $RC -eq 0 && -n "$AGENT_JSON" ]]; then
    break
  fi
  sleep 2
  
  # If still failing, continue retry
  if [[ $i -eq 3 ]]; then
    echo "Agent failed (rc=$RC): $AGENT_ERR" >&2
  fi
done

REPLY_TEXT=$(python3 - <<'PY'
import json
p='/tmp/x_agent_reply.json'
try:
    obj=json.load(open(p,'r',encoding='utf-8'))
    text=''
    # Newer openclaw JSON shape
    if isinstance(obj, dict):
        payloads = obj.get('payloads')
        if isinstance(payloads, list) and payloads:
            text = (payloads[0].get('text') or '').strip()
    # Backward-compatible fallback
    if not text and isinstance(obj, dict):
        text = (obj.get('result',{}).get('payloads',[{}])[0].get('text') or '').strip()
    print(text)
except Exception:
    print('')
PY
)
# normalize escaped newlines like "\\n" into real line breaks
REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"

if [[ -z "$REPLY_TEXT" ]]; then
  echo "Agent returned empty reply" >&2
  exit 1
fi

export REPLY_TEXT

# 3) Reply via X-CDP (fixed port 44407)
NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407 | tee -a /tmp/x_fast_reply_post.log

# 4) Append local evidence log
python3 - <<'PY'
import json, time, os
path='/root/.openclaw/workspace/data/x_reply_log.jsonl'
obj={
  'ts': int(time.time()),
  'target_url': os.environ.get('TARGET_URL',''),
  'tweet_text': os.environ.get('TWEET_TEXT','')[:280],
  'reply_text': os.environ.get('REPLY_TEXT','')[:280]
}
with open(path,'a',encoding='utf-8') as f:
  f.write(json.dumps(obj, ensure_ascii=False)+'\n')
PY
