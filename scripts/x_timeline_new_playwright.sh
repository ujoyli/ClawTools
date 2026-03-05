#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
COOKIE_FILE="/home/browserwing/cookie.json"

exec 9>/tmp/x_timeline_new_playwright.lock
flock -n 9 || exit 0

# 1) Pick hot tweet via Python Playwright (fresh browser session)
PICK_JSON=$(python3 "$WORKDIR/scripts/PickHotTweet_PW.py" --cookie-file "$COOKIE_FILE" --replied-file "$WORKDIR/data/x_replied_targets.json" 2>/tmp/x_timeline_new_pw_pick.err || true)
printf '%s' "$PICK_JSON" > /tmp/x_timeline_new_pw_pick.json
if [[ -z "$PICK_JSON" ]]; then
  echo "Picker returned empty output"
  cat /tmp/x_timeline_new_pw_pick.err || true
  exit 1
fi
OK=$(echo "$PICK_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))' 2>/dev/null || echo False)
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

# 2) Generate reply
PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "$HANDLE" "$TWEET_TEXT")
AGENT_JSON=$(openclaw agent --session-id x-timeline-new-pw --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/tmp/x_timeline_new_pw_agent.err || true)
printf '%s' "$AGENT_JSON" > /tmp/x_timeline_new_pw_reply.json

REPLY_TEXT=$(python3 - <<'PY'
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
)
REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"
if [[ -z "$REPLY_TEXT" ]]; then
  echo "Empty reply"
  exit 1
fi

echo "Reply: $REPLY_TEXT"

# 3) Post reply via Python Playwright (fresh browser session)
POST_JSON=$(python3 "$WORKDIR/scripts/PostTweet_Reply_PW.py" --cookie-file "$COOKIE_FILE" --url "$TARGET_URL" --reply "$REPLY_TEXT")
POST_OK=$(echo "$POST_JSON" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("ok",False))' 2>/dev/null || echo False)
if [[ "$POST_OK" != "True" ]]; then
  echo "Post failed: $POST_JSON"
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