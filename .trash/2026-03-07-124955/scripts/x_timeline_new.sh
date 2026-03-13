#!/usr/bin/env bash
# Experimental timeline viral responder (x-algorithm based)
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
export NODE_PATH=/tmp/node_modules

source "$WORKDIR/scripts/ensure_x_cookie.sh" >/tmp/ensure_cookie_timeline_new.log 2>&1 || true
source "$WORKDIR/scripts/ensure_chromium.sh" >/tmp/ensure_chromium_timeline_new.log 2>&1 || true

exec 9>/tmp/x_timeline_new.lock
flock -n 9 || exit 0

REPLIED_FILE="$WORKDIR/data/x_replied_targets.json"
REPLY_LOG="$WORKDIR/data/x_reply_log.jsonl"

TWEETS=$(NODE_PATH=/tmp/node_modules timeout 120 node -e '
const puppeteer=require("puppeteer-core"),fs=require("fs");
(async()=>{
  const b=await puppeteer.connect({browserURL:"http://localhost:44407"});
  const page=(await b.pages())[0]||await b.newPage();
  const raw=JSON.parse(fs.readFileSync("/home/browserwing/cookie.json","utf8"));
  for(const c of raw)await page.setCookie({name:c.name,value:c.value,domain:c.domain,path:c.path||"/",httpOnly:!!c.httpOnly,secure:!!c.secure,...(c.expirationDate?{expires:Math.floor(c.expirationDate)}:{})});

  try {
    await page.goto("https://x.com/home",{waitUntil:"domcontentloaded",timeout:60000});
  } catch(e) {
    await page.goto("https://twitter.com/home",{waitUntil:"domcontentloaded",timeout:60000});
  }
  await new Promise(r=>setTimeout(r,5000));
  try { await page.reload({waitUntil:"domcontentloaded",timeout:60000}); } catch(e) {}
  await new Promise(r=>setTimeout(r,3500));

  const tweets=await page.evaluate(()=>{
    return [...document.querySelectorAll("article[data-testid=\"tweet\"]")].slice(0,40).map(a=>{
      const text=(a.querySelector("[data-testid=\"tweetText\"]")?.textContent||"");
      const time=a.querySelector("time")?.getAttribute("datetime")||"";
      const link=[...a.querySelectorAll("a[href*=\"/status/\"]")].find(l=>l.querySelector("time"));
      const url=link?link.href:"";
      const tid=url.match(/status\/(\d+)/)?.[1]||"";
      const hasMedia=!!a.querySelector("[data-testid=\"tweetPhoto\"], video, [data-testid=\"card.wrapper\"]");
      const hasExternalLink=[...a.querySelectorAll("a[href]")].some(x=>{
        const h=x.getAttribute("href")||"";
        return /^https?:\/\//.test(h) && !/x\.com|twitter\.com/.test(h);
      });
      const isReply=/^replying to/i.test((a.innerText||""));
      const ve=a.querySelector("a[href*=\"/analytics\"]");
      const views=ve?parseInt((ve.textContent||"0").replace(/[^\d]/g,""))||0:0;
      const gs=[...a.querySelectorAll("[role=\"group\"] [data-testid]")];
      const g=k=>{const e=gs.find(x=>(x.getAttribute("data-testid")||"").includes(k));const s=e?(e.getAttribute("aria-label")||e.textContent||"0"):"0";const m=s.match(/([\d,.]+)/);return m?parseInt(m[1].replace(/,/g,""))||0:0};
      const likes=g("like"),rt=g("retweet"),replies=g("reply");
      const q= /\?|？/.test(text);
      const controversy= /(unpopular|hot take|错了|离谱|垃圾|骗局|崩了|完蛋|bullshit|scam|fake)/i.test(text);
      return {text,time,url,tid,views,likes,rt,replies,hasMedia,hasExternalLink,isReply,hasQuestion:q,controversy};
    }).filter(t=>t.url&&t.tid&&t.text.length>=12);
  });

  console.log(JSON.stringify(tweets));
  await b.disconnect();
})();
' 2>/tmp/x_timeline_new_scrape.err || echo "[]")

TARGET_INFO=$(printf '%s' "$TWEETS" | python3 - <<'PY'
import json,time,math,os,re
from datetime import datetime,timezone

raw=input().strip() if False else None
import sys
raw=sys.stdin.read().strip() or "[]"
try:
    arr=json.loads(raw)
except:
    arr=[]

replied_path='/root/.openclaw/workspace/data/x_replied_targets.json'
now=int(time.time())
window=72*3600
try:
    replied=json.load(open(replied_path)).get('replied',{})
    replied={k:v for k,v in replied.items() if isinstance(v,int) and now-v<window}
except:
    replied={}

best=None
for t in arr:
    tid=t.get('tid','')
    if not tid or tid in replied: continue
    txt=t.get('text','')
    if len(re.findall(r'[\u4e00-\u9fffA-Za-z]',txt))<8: continue
    age_min=60
    ts=t.get('time','')
    if ts:
      try:
        dt=datetime.fromisoformat(ts.replace('Z','+00:00'))
        age_min=max(1,(datetime.now(timezone.utc)-dt).total_seconds()/60)
      except: pass
    if age_min>180: continue

    # Hard rule from 大帅: only reply to tweets <=3h and views > 1000
    views=t.get('views',0)
    if views<=1000: continue

    # x-algorithm inspired score
    likes=t.get('likes',0); rt=t.get('rt',0); replies=t.get('replies',0)
    velocity=(views+1)/age_min
    engage=replies*8 + rt*5 + likes*2 + velocity*0.8
    score=engage
    if t.get('hasMedia'): score+=60
    if t.get('hasQuestion'): score+=45
    if t.get('controversy'): score+=35
    if t.get('hasExternalLink'): score-=40
    if t.get('isReply'): score-=20

    t['score']=round(score,2)
    t['ageMin']=round(age_min,1)
    if best is None or t['score']>best['score']:
        best=t

if not best:
    print("")
    raise SystemExit

replied[best['tid']]=now
with open(replied_path,'w') as f:
    json.dump({'replied':replied},f,ensure_ascii=False);f.write('\n')
print(json.dumps(best,ensure_ascii=False))
PY
)

if [[ -z "$TARGET_INFO" ]]; then
  echo "No suitable viral targets"
  exit 75
fi

TARGET_URL=$(echo "$TARGET_INFO" | python3 -c 'import json,sys;d=json.loads(sys.stdin.read());print(d.get("url",""))')
TWEET_TEXT=$(echo "$TARGET_INFO" | python3 -c 'import json,sys;d=json.loads(sys.stdin.read());print(d.get("text",""))')
HANDLE=$(echo "$TARGET_INFO" | python3 -c 'import json,sys,re;d=json.loads(sys.stdin.read());u=d.get("url","");m=re.search(r"x.com/([^/]+)/status",u);print(m.group(1) if m else "")')
SCORE=$(echo "$TARGET_INFO" | python3 -c 'import json,sys;d=json.loads(sys.stdin.read());print(f"score={d.get("score",0)} views={d.get("views",0)} age={d.get("ageMin",0)}m")')

export TARGET_URL TWEET_TEXT HANDLE

echo "Target: @$HANDLE $TARGET_URL ($SCORE)"

PROMPT=$(python3 "$WORKDIR/scripts/gen_reply_prompt.py" "$HANDLE" "$TWEET_TEXT")
AGENT_JSON=$(openclaw agent --session-id x-timeline-new --thinking minimal --timeout 120 --json --message "$PROMPT" 2>/tmp/x_timeline_new_agent.err || true)
printf '%s' "$AGENT_JSON" > /tmp/x_timeline_new_reply.json

REPLY_TEXT=$(python3 - <<'PY'
import json
try:
  obj=json.load(open('/tmp/x_timeline_new_reply.json'))
  if isinstance(obj,dict):
    p=obj.get('payloads',[])
    if p and p[0].get('text'): print((p[0].get('text') or '').strip()); raise SystemExit
    print((obj.get('result',{}).get('payloads',[{}])[0].get('text') or '').strip())
except: pass
PY
)
REPLY_TEXT="${REPLY_TEXT//\\n/$'\n'}"

if [[ -z "$REPLY_TEXT" ]]; then
  echo "Empty reply" >&2
  exit 1
fi

echo "Reply: $REPLY_TEXT"
NODE_PATH=/tmp/node_modules node "$WORKDIR/skills/x-cdp/scripts/reply-tweet.js" "$TARGET_URL" "$REPLY_TEXT" --port 44407 | tee -a /tmp/x_timeline_new_post.log

python3 - <<'PY'
import json,time,os
obj={
  'ts':int(time.time()),
  'source':'timeline_new',
  'handle':os.environ.get('HANDLE',''),
  'target_url':os.environ.get('TARGET_URL',''),
  'tweet_text':os.environ.get('TWEET_TEXT',''),
  'reply_text':os.environ.get('REPLY_TEXT','')
}
with open('/root/.openclaw/workspace/data/x_reply_log.jsonl','a') as f:
  f.write(json.dumps(obj,ensure_ascii=False)+'\n')
PY

echo "Done: replied to @$HANDLE (timeline new)"