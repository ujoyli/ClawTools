#!/usr/bin/env bash
# Scrape own timeline for viral-potential tweets and reply
set -uo pipefail
WORKDIR="/root/.openclaw/workspace"
# Ensure X cookie is set
source "$WORKDIR/scripts/ensure_x_cookie.sh" > /tmp/ensure_cookie_timeline.log 2>&1 || true
export NODE_PATH=/tmp/node_modules

# Ensure Chromium is running properly
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_timeline.log 2>&1 || true

exec 9>/tmp/x_timeline_viral.lock
flock -n 9 || exit 0

REPLIED_FILE="$WORKDIR/data/x_replied_targets.json"
REPLY_LOG="$WORKDIR/data/x_reply_log.jsonl"

# 1) Scrape timeline via CDP - get tweets with engagement metrics
TWEETS=$(NODE_PATH=/tmp/node_modules timeout 120 node -e '
const puppeteer=require("puppeteer-core"),fs=require("fs");
(async()=>{
  const b=await puppeteer.connect({browserURL:"http://localhost:44407"});
  const page=(await b.pages())[0]||await b.newPage();
  const raw=JSON.parse(fs.readFileSync("/home/browserwing/cookie.json","utf8"));
  for(const c of raw)await page.setCookie({name:c.name,value:c.value,domain:c.domain,path:c.path||"/",httpOnly:!!c.httpOnly,secure:!!c.secure,...(c.expirationDate?{expires:Math.floor(c.expirationDate)}:{})});

  await page.goto("https://x.com/home",{waitUntil:"networkidle2",timeout:40000});
  await new Promise(r=>setTimeout(r,3000));
  // 强制刷新一次，确保拿到最新时间线
  await page.reload({waitUntil:"networkidle2",timeout:40000});
  await new Promise(r=>setTimeout(r,2500));

  const tweets=await page.evaluate(()=>{
    return[...document.querySelectorAll("article[data-testid=\"tweet\"]")].slice(0,30).map(a=>{
      const text=(a.querySelector("[data-testid=\"tweetText\"]")?.textContent||"");
      const time=a.querySelector("time")?.getAttribute("datetime")||"";
      const handleEl=[...a.querySelectorAll("a[role=\"link\"]")].find(l=>/^\/@?\w+$/.test(l.getAttribute("href")||""));
      const handle=handleEl?(handleEl.getAttribute("href")||"").replace(/^\//,"").replace(/^@/,""):"";
      const link=[...a.querySelectorAll("a[href*=\"/status/\"]")].find(l=>l.querySelector("time"));
      const url=link?link.href:"";
      const tid=url.match(/status\/(\d+)/)?.[1]||"";
      // Engagement
      const gs=[...a.querySelectorAll("[role=\"group\"] [data-testid]")];
      const g=k=>{const e=gs.find(x=>(x.getAttribute("data-testid")||"").includes(k));const s=e?(e.getAttribute("aria-label")||e.textContent||"0"):"0";const m=s.match(/([\d,.]+)/);return m?parseInt(m[1].replace(/,/g,""))||0:0};
      const ve=a.querySelector("a[href*=\"/analytics\"]");
      const views=ve?parseInt((ve.textContent||"0").replace(/[^\d]/g,""))||0:0;
      const likes=g("like"),rt=g("retweet"),replies=g("reply");
      // Viral score: no log on views + time-decay via per-minute exposure
      let ageMin = 30;
      if (time) {
        const ms = Date.now() - new Date(time).getTime();
        ageMin = Math.max(1, Math.floor(ms / 60000));
      }
      const viewsPerMin = views > 0 ? (views / ageMin) : 0;
      // 发布时间越短加成越高：30m内最高，其后递减
      const freshnessBoost = ageMin <= 30 ? 80 : (ageMin <= 60 ? 45 : (ageMin <= 120 ? 20 : (ageMin <= 240 ? 8 : 0)));
      const score = viewsPerMin*3 + likes*8 + rt*20 + replies*15 + freshnessBoost;
      return{handle,text,time,url:tid?"https://x.com/"+handle+"/status/"+tid:"",tweetId:tid,views,likes,rt,replies,ageMin,viewsPerMin,freshnessBoost,score};
    }).filter(t=>t.tweetId&&t.handle);
  });

  // Sort by score desc
  tweets.sort((a,b)=>b.score-a.score);
  console.log(JSON.stringify(tweets));
  b.disconnect();
})().catch(e=>{console.error(e.message);console.log("[]")});
' 2>/dev/null | grep '^\[' | head -1 || echo '[]')

# 2) Pick top-scored unreplied tweet (after ranking)
TARGET_INFO=$(python3 - "$TWEETS" <<'PYEND'
import json, sys, time, os
from datetime import datetime, timezone

tweets = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
replied_path = "/root/.openclaw/workspace/data/x_replied_targets.json"
now = time.time()
window = 72 * 3600

try:
    replied = json.load(open(replied_path)).get("replied", {})
    replied = {k: v for k, v in replied.items() if isinstance(v, int) and now - v < window}
except:
    replied = {}

MIN_SCORE = 50  # At least some engagement
BLACKLIST = ["whyyoutouzhele", "teacherli1", "liteacher", "lixiansheng"]

# tweets already sorted by score desc in JS side; iterate in order and take first valid
for t in tweets:
    handle = t.get("handle", "").lower()
    # Skip blacklisted accounts
    if any(b in handle for b in BLACKLIST):
        continue
    
    tid = t.get("tweetId", "")
    if not tid or tid in replied:
        continue
    if t.get("score", 0) < MIN_SCORE:
        continue
    # Skip very old tweets (> 6h) - want fresh content
    tweet_time = t.get("time", "")
    if tweet_time:
        try:
            dt = datetime.fromisoformat(tweet_time.replace("Z", "+00:00"))
            age_h = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
            if age_h > 6:
                continue
        except:
            pass
    # Skip if text too short (likely media-only)
    text = t.get("text", "")
    if len(text) < 15:
        continue

    # 中文优先：只回复中文推文（至少包含2个中文字符）
    import re
    if len(re.findall(r'[\u4e00-\u9fff]', text)) < 2:
        continue

    print(json.dumps(t, ensure_ascii=False))
    replied[tid] = int(now)
    with open(replied_path, "w") as f:
        json.dump({"replied": replied}, f, ensure_ascii=False)
        f.write("\n")
    break
PYEND
)

if [[ -z "$TARGET_INFO" ]]; then
  echo "No viral timeline tweets to reply"
  exit 75  # EX_TEMPFAIL - no action taken, don't notify
fi

TARGET_URL=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('url',''))")
TWEET_TEXT=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('text',''))")
HANDLE=$(echo "$TARGET_INFO" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('handle',''))")
SCORE=$(echo "$TARGET_INFO" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(f\"👁{d.get('views',0)} ({d.get('viewsPerMin',0):.1f}/min) ❤️{d.get('likes',0)} 🔁{d.get('rt',0)} 💬{d.get('replies',0)} age={d.get('ageMin',0)}m boost={d.get('freshnessBoost',0)} score={d.get('score',0):.0f}\")")

export TARGET_URL TWEET_TEXT HANDLE
echo "Target: @$HANDLE $TARGET_URL ($SCORE)"

# 3) Generate reply
PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "$HANDLE" "$TWEET_TEXT")

AGENT_JSON=""
for i in 1 2 3; do
  set +e
  AGENT_JSON=$(openclaw agent --session-id x-timeline-reply --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/dev/null)
  RC=$?
  set -e
  printf '%s' "$AGENT_JSON" > /tmp/x_timeline_reply.json
  if [[ $RC -eq 0 && -n "$AGENT_JSON" ]]; then break; fi
  sleep 2
done

REPLY_TEXT=$(python3 - <<'PYEXTRACT'
import json
try:
    obj = json.load(open("/tmp/x_timeline_reply.json"))
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

# 4) Post
NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407

# 5) Log
python3 -c "
import json,time,os
obj={'ts':int(time.time()),'source':'timeline','handle':os.environ.get('HANDLE',''),'target_url':os.environ.get('TARGET_URL',''),'tweet_text':os.environ.get('TWEET_TEXT','')[:280],'reply_text':os.environ.get('REPLY_TEXT','')[:280]}
with open('/root/.openclaw/workspace/data/x_reply_log.jsonl','a') as f:
  f.write(json.dumps(obj,ensure_ascii=False)+'\n')
"
echo "Done: replied to @$HANDLE (timeline viral)"

# Send Discord notification only on successful reply
openclaw message send --channel discord --target channel:1476191544808837192 --message "✅ 时间线爆款回复 @$HANDLE

推文：$TARGET_URL
回复：$REPLY_TEXT" 2>/dev/null || true
