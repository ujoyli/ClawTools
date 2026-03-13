#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
COOKIE_FILE="/home/browserwing/cookie.json"

exec 9>/tmp/x_timeline_new_playwright.lock
flock -n 9 || exit 0

# 1) Pick hot tweet via Python Playwright (fresh browser session)
# If not found once, refresh/retry a few times.
PICK_JSON=""
OK="False"
MAX_PICK_TRIES=4
for pick_try in $(seq 1 $MAX_PICK_TRIES); do
  PICK_JSON=$(python3 "$WORKDIR/scripts/PickHotTweet_PW.py" --cookie-file "$COOKIE_FILE" --replied-file "$WORKDIR/data/x_replied_targets.json" --max-age-min 120 --min-views 10000 2>/tmp/x_timeline_new_pw_pick.err || true)
  printf '%s' "$PICK_JSON" > /tmp/x_timeline_new_pw_pick.json

  if [[ -z "$PICK_JSON" ]]; then
    echo "Picker returned empty output (try $pick_try/$MAX_PICK_TRIES)"
    cat /tmp/x_timeline_new_pw_pick.err || true
    sleep 3
    continue
  fi

  OK=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))' 2>/dev/null || echo False)
  if [[ "$OK" == "True" ]]; then
    break
  fi

  echo "No qualified target (try $pick_try/$MAX_PICK_TRIES): $PICK_JSON"
  sleep 3
done

if [[ "$OK" != "True" ]]; then
  echo "$PICK_JSON"
  cat /tmp/x_timeline_new_pw_pick.err || true
  exit 75
fi

TARGET_URL=$(python3 - <<'PY'
import json
p='/tmp/x_timeline_new_pw_pick.json'
d=json.load(open(p,'r',encoding='utf-8'))
print(d.get('url',''))
PY
)
TWEET_TEXT=$(python3 - <<'PY'
import json
p='/tmp/x_timeline_new_pw_pick.json'
d=json.load(open(p,'r',encoding='utf-8'))
print(d.get('text',''))
PY
)
HANDLE=$(python3 - <<'PY'
import json,re
p='/tmp/x_timeline_new_pw_pick.json'
d=json.load(open(p,'r',encoding='utf-8'))
u=d.get('url','')
m=re.search(r'x.com/([^/]+)/status',u)
print(m.group(1) if m else '')
PY
)
SCORE=$(python3 - <<'PY'
import json
p='/tmp/x_timeline_new_pw_pick.json'
d=json.load(open(p,'r',encoding='utf-8'))
print(f"score={d.get('score',0)} views={d.get('views',0)} age={d.get('ageMin',0)}m")
PY
)

echo "Target: @$HANDLE $TARGET_URL ($SCORE)"

# Hard rule: only reply if age <= 2h and views > 5000, otherwise skip (no fallback)
read -r AGE_MIN VIEWS <<<"$(python3 - <<'PY'
import json
p='/tmp/x_timeline_new_pw_pick.json'
d=json.load(open(p,'r',encoding='utf-8'))
print(f"{float(d.get('ageMin', 99999))} {int(d.get('views', 0))}")
PY
)"
if ! python3 - <<PY
age=float("$AGE_MIN")
views=int("$VIEWS")
raise SystemExit(0 if (age<=120 and views>10000) else 1)
PY
then
  echo "Skip this round: age=${AGE_MIN}m views=${VIEWS} (require age<=120m and views>10000)"
  exit 75
fi

# 2) Generate reply with retry loop (max 3 attempts)
# CRITICAL: Clear stale reply JSON before each run to prevent reuse
rm -f /tmp/x_timeline_new_pw_reply.json /tmp/x_timeline_new_pw_agent.err

generate_reply() {
  local attempt=$1
  local PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "$HANDLE" "$TWEET_TEXT")
  local SESSION_ID="x-timeline-new-$(date +%s)-${attempt}"
  local AGENT_JSON=$(openclaw agent --session-id "$SESSION_ID" --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/tmp/x_timeline_new_pw_agent.err || true)
  # Only write if we got actual output (not empty)
  if [[ -n "$AGENT_JSON" ]]; then
    printf '%s' "$AGENT_JSON" > /tmp/x_timeline_new_pw_reply.json
  fi

  python3 - <<'PY'
import json
try:
  obj=json.load(open('/tmp/x_timeline_new_pw_reply.json'))
  if isinstance(obj,dict):
    p=obj.get('payloads',[])
    if p and p[0].get('text'):
      print((p[0].get('text') or '').strip())
      raise SystemExit
    print((obj.get('result',{}).get('payloads',[{}])[0].get('text') or '').strip())
except:
  pass
PY
}

validate_reply() {
  local text="$1"
  local flattened=$(printf '%s' "$text" | tr '\n' ' ')
  # Extended patterns including common status report phrases
  if printf '%s' "$flattened" | grep -qiE "系统状态 | 当前状态 | 任务状态 | 定时任务|Chrome 进程 | 脚本执行 | 大帅|✅|##|Posted the reply|Next steps|continue automatically|Do you want me|I will continue|same pattern|timeline picker|Monitor Chrome|Log each posted|Pick one|I'll proceed|successfully|completed|finished|error|failed|timeout|running|status|report|日志 | 执行 | 完成 | 失败 | 超时 | 运行 | 状态 | 报告|I'll|I will|Let me|我会 | 我将 | 下一步 | 继续 | 等待 | 确认"; then
    return 1  # Invalid
  fi
  # Check for questions (status reports often ask questions)
  if printf '%s' "$flattened" | grep -qE "\?|？|Do you want|Would you|Should I|要不要 | 可以吗 | 行吗"; then
    return 1  # Invalid
  fi
  # Check for excessive length (must be <= 80 chars)
  if [[ ${#text} -gt 80 ]]; then
    echo "Attempt $attempt: Reply too long (${#text} chars, max 80), retrying..."
    return 1  # Invalid
  fi
  return 0  # Valid
}

REPLY_TEXT=""
for attempt in 1 2 3; do
  REPLY_TEXT=$(generate_reply $attempt)
  REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"
  
  if [[ -z "$REPLY_TEXT" ]]; then
    echo "Attempt $attempt: Empty reply"
    continue
  fi
  
  # Check length first (most common failure)
  if [[ ${#REPLY_TEXT} -gt 80 ]]; then
    echo "Attempt $attempt: Reply too long (${#REPLY_TEXT} chars, max 80), retrying..."
    REPLY_TEXT=""
    continue
  fi
  
  if validate_reply "$REPLY_TEXT"; then
    echo "Attempt $attempt: Valid reply generated"
    break
  else
    echo "Attempt $attempt: Invalid reply (status report pattern detected), retrying..."
    REPLY_TEXT=""
  fi
done

if [[ -z "$REPLY_TEXT" ]]; then
  echo "Agent failed after 3 attempts, skip this round (no fallback)"
  exit 75
fi

echo "Reply: $REPLY_TEXT"

# 3) Post reply via Python Playwright (fresh browser session)
# Retry on transient Playwright/pipe failures (e.g. EPIPE)
POST_OK="False"
POST_JSON=""
for post_try in 1 2 3; do
  POST_JSON=$(python3 "$WORKDIR/scripts/PostTweet_Reply_PW.py" --cookie-file "$COOKIE_FILE" --url "$TARGET_URL" --reply "$REPLY_TEXT" 2>&1 || true)
  POST_OK=$(echo "$POST_JSON" | python3 -c 'import json,sys; s=sys.stdin.read();
try:
 d=json.loads(s); print(d.get("ok",False))
except:
 print(False)')

  if [[ "$POST_OK" == "True" ]]; then
    echo "Post attempt $post_try: success"
    break
  fi

  echo "Post attempt $post_try failed"
  echo "$POST_JSON"
  # Retry only for transient transport/browser errors
  if printf '%s' "$POST_JSON" | grep -qiE "EPIPE|pipe|Target page, context or browser has been closed|timeout|ECONNRESET|browser has been closed"; then
    sleep 2
    continue
  fi
  break
 done

if [[ "$POST_OK" != "True" ]]; then
  echo "Post failed after retries: $POST_JSON"
  exit 1
fi

# 4) Log
export TARGET_URL TWEET_TEXT HANDLE REPLY_TEXT
python3 - <<'PY'
import json,time,os
obj={
  'ts':int(time.time()),
  'source':'timeline_new_playwright',
  'handle':os.environ.get('HANDLE',''),
  'target_url':os.environ.get('TARGET_URL',''),
  'tweet_text':os.environ.get('TWEET_TEXT',''),
  'reply_text':os.environ.get('REPLY_TEXT','')
}
with open('/root/.openclaw/workspace/data/x_reply_log.jsonl','a') as f:
  f.write(json.dumps(obj,ensure_ascii=False)+'\n')
PY

echo "Done: replied to @$HANDLE (timeline new playwright)"