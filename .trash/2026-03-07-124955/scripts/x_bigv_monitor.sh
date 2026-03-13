#!/usr/bin/env bash
# Monitor big V accounts, reply to their latest tweets ASAP
set -uo pipefail
WORKDIR="/root/.openclaw/workspace"
# Ensure X cookie is set
source "$WORKDIR/scripts/ensure_x_cookie.sh" > /tmp/ensure_cookie_bigv.log 2>&1 || true
export NODE_PATH=/tmp/node_modules

# Ensure Chromium is running properly
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_bigv.log 2>&1 || true

exec 9>/tmp/x_bigv_monitor.lock
flock -n 9 || exit 0

BIGV_LIST="dotey vista8 lxfater yaborobot op7418 HiTw93 real_kai42 JefferyTatworker lidangzzz maoshen mranti"
REPLIED_FILE="$WORKDIR/data/x_replied_targets.json"
REPLY_LOG="$WORKDIR/data/x_reply_log.jsonl"

# 1) For each big V, get their latest tweet via CDP
TARGETS=$(NODE_PATH=/tmp/node_modules timeout 300 node -e '
const puppeteer=require("puppeteer-core"),fs=require("fs");
const handles=process.argv[1].split(" ");
(async()=>{
  const b=await puppeteer.connect({browserURL:"http://localhost:44407"});
  const page=(await b.pages())[0]||await b.newPage();
  const cookiePath = process.getuid() === 0 ? "/root/cookie.json" : "/home/browserwing/cookie.json";
  const raw=JSON.parse(fs.readFileSync(cookiePath,"utf8"));
  for(const c of raw)await page.setCookie({name:c.name,value:c.value,domain:c.domain,path:c.path||"/",httpOnly:!!c.httpOnly,secure:!!c.secure,...(c.expirationDate?{expires:Math.floor(c.expirationDate)}:{})});

  const results=[];
  for(const h of handles){
    try{
      await page.goto("https://x.com/"+h,{waitUntil:"networkidle2",timeout:30000});
      await new Promise(r=>setTimeout(r,3000));
      const tweet=await page.evaluate((handle)=>{
        const articles=[...document.querySelectorAll("article[data-testid=\"tweet\"]")];
        for(const a of articles.slice(0,3)){
          // Skip pinned
          if(a.querySelector("[data-testid=\"socialContext\"]")?.textContent?.includes("置顶"))continue;
          if(a.querySelector("[data-testid=\"socialContext\"]")?.textContent?.includes("Pinned"))continue;
          const text=(a.querySelector("[data-testid=\"tweetText\"]")?.textContent||"").substring(0,500);
          const time=a.querySelector("time")?.getAttribute("datetime")||"";
          const link=[...a.querySelectorAll("a[href*=\"/status/\"]")].find(l=>l.querySelector("time"));
          const url=link?link.href:"";
          const tid=url.match(/status\/(\d+)/)?.[1]||"";
          if(tid)return{handle,text,time,url:"https://x.com/"+handle+"/status/"+tid,tweetId:tid};
        }
        return null;
      },h);
      if(tweet)results.push(tweet);
    }catch(e){console.error(h+":",e.message)}
  }
  console.log(JSON.stringify(results));
  b.disconnect();
})().catch(e=>{console.error(e.message);console.log("[]")});
' "$BIGV_LIST" 2>/dev/null | grep '^\[' | head -1 || echo '[]')

# 2) Filter unreplied, recent (< 6h)
TARGET_INFO=$(python3 - "$TARGETS" <<'PYEND'
import json, sys, time, re
from datetime import datetime, timezone

targets = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
replied_path = "/root/.openclaw/workspace/data/x_replied_targets.json"
now = time.time()
window = 72 * 3600

try:
    replied = json.load(open(replied_path)).get("replied", {})
    replied = {k: v for k, v in replied.items() if isinstance(v, int) and now - v < window}
except:
    replied = {}

def parse_tweet_time(time_str):
    """Parse X tweet time in various formats"""
    if not time_str:
        return None
    try:
        # ISO format: 2026-02-28T15:30:00.000Z
        return datetime.fromisoformat(time_str.replace("Z", "+00:00"))
    except:
        pass
    try:
        # X alternative format: Sat Feb 28 15:30:00 +0000 2026
        return datetime.strptime(time_str, "%a %b %d %H:%M:%S %z %Y")
    except:
        pass
    try:
        # Extract numbers and build datetime
        nums = re.findall(r'\d+', time_str)
        if len(nums) >= 6:
            return datetime(int(nums[0]), int(nums[1]), int(nums[2]), int(nums[3]), int(nums[4]), int(nums[5]))
    except:
        pass
    return None

# Blacklist - never reply to these accounts
BLACKLIST = ["whyyoutouzhele", "teacherli1", "liteacher", "lixiansheng"]

found = None
for t in targets:
    handle = t.get("handle", "").lower()
    tid = t.get("tweetId", "")
    
    # Skip blacklisted accounts
    if any(b in handle for b in BLACKLIST):
        print(f"DEBUG: Skipping blacklisted @{handle}", file=sys.stderr)
        continue
    
    if not tid:
        continue
    if tid in replied:
        continue
    
    # Check if tweet is recent (< 6h)
    tweet_time = t.get("time", "")
    if tweet_time:
        dt = parse_tweet_time(tweet_time)
        if dt:
            age_h = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
            if age_h > 6 or age_h < 0:
                print(f"DEBUG: Skipping {tid} age={age_h:.1f}h", file=sys.stderr)
                continue
        else:
            print(f"DEBUG: Cannot parse time for {tid}: {tweet_time}", file=sys.stderr)
    
    # Found a fresh unreplied big V tweet
    found = t
    print(json.dumps(t, ensure_ascii=False))
    
    # Mark as replied
    replied[tid] = int(now)
    with open(replied_path, "w") as f:
        json.dump({"replied": replied}, f, ensure_ascii=False)
        f.write("\n")
    break

if not found:
    print(f"DEBUG: No fresh tweets found. Targets: {len(targets)}, Replied: {len(replied)}", file=sys.stderr)
PYEND
)

if [[ -z "$TARGET_INFO" ]]; then
  echo "No fresh unreplied big V tweets"
  exit 75  # EX_TEMPFAIL - no action taken, don't notify
fi

TARGET_URL=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('url',''))")
TWEET_TEXT=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('text','')[:400])")
HANDLE=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('handle',''))")

export TARGET_URL TWEET_TEXT HANDLE
echo "Target: @$HANDLE $TARGET_URL"

# 3) Generate reply
PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "$HANDLE" "$TWEET_TEXT")

AGENT_JSON=""
for i in 1 2 3; do
  set +e
  AGENT_JSON=$(openclaw agent --session-id x-bigv-reply --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/tmp/x_agent_err.log)
  RC=$?
  set -e
  printf '%s' "$AGENT_JSON" > /tmp/x_bigv_reply.json
  if [[ $RC -eq 0 && -n "$AGENT_JSON" ]]; then break; fi
  sleep 2
done

REPLY_TEXT=$(python3 - <<'PYEXTRACT'
import json
try:
    obj = json.load(open("/tmp/x_bigv_reply.json"))
    if isinstance(obj, dict):
        p = obj.get("payloads", [])
        if p:
            t = p[0].get("text", "")
        else:
            r = obj.get("result", {})
            pp = r.get("payloads", [{}])
            t = pp[0].get("text", "") if pp else ""
        print(t.strip())
except:
    pass
PYEXTRACT
)
# normalize escaped newlines like "\\n" into real line breaks
REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"

if [[ -z "$REPLY_TEXT" ]]; then
  echo "Empty reply" >&2
  exit 1
fi

export REPLY_TEXT
echo "Reply: $REPLY_TEXT"

# 4) Post reply via CDP
NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407 | tee -a /tmp/x_bigv_reply_post.log

# 5) Log
python3 -c "
import json,time,os
obj={'ts':int(time.time()),'source':'bigv','handle':os.environ.get('HANDLE',''),'target_url':os.environ.get('TARGET_URL',''),'tweet_text':os.environ.get('TWEET_TEXT','')[:280],'reply_text':os.environ.get('REPLY_TEXT','')[:280]}
with open('/root/.openclaw/workspace/data/x_reply_log.jsonl','a') as f:
  f.write(json.dumps(obj,ensure_ascii=False)+'\n')
"

echo "Done: replied to @$HANDLE"

# Send Discord notification only on successful reply
openclaw message send --channel discord --target channel:1476191544808837192 --message "✅ 已回复 @$HANDLE

推文：$TARGET_URL
回复：$REPLY_TEXT" 2>/dev/null || true
