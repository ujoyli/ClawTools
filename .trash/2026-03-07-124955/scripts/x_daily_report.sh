#!/usr/bin/env bash
# X Daily Report - scrapes analytics page for real engagement data
set -uo pipefail
WORKDIR="/root/.openclaw/workspace"
export NODE_PATH=/tmp/node_modules

# 0) System snapshot (merge old morning-report into this report)
NOW=$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')
HOST=$(hostname)
UPTIME_LINE=$(uptime -p 2>/dev/null || echo 'N/A')
LOAD_LINE=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo 'N/A')
MEM_SUMMARY=$(free -h 2>/dev/null | awk 'NR==2{print "used=" $3 ", free=" $4 ", avail=" $7}' || echo 'N/A')
DISK_SUMMARY=$(df -h / 2>/dev/null | awk 'NR==2{print "used=" $3 "/" $2 " (" $5 ")"}' || echo 'N/A')
WEATHER=$(curl -s "wttr.in/Shanghai?format=%c+%t+%h+%w" 2>/dev/null || echo 'N/A')

# 1) Scrape analytics (profile posts in last 7 days)
source "$WORKDIR/scripts/ensure_chromium.sh" >/tmp/ensure_chromium_daily.log 2>&1 || true
bash "$WORKDIR/tmp/start_chromium.sh" >/tmp/start_chromium_daily.log 2>&1 || true
REPORT_DAY=$(TZ=Asia/Shanghai date -d "yesterday" +%Y-%m-%d)
export REPORT_DAY
cat >/tmp/x_daily_analytics.js <<'NODE'
const puppeteer = require("puppeteer-core");
const fs = require("fs");

function parseNum(x){
  if(!x) return 0;
  const m = String(x).replace(/,/g,"").match(/([\d.]+)\s*([KkMm万]?)/);
  if(!m) return 0;
  let v = parseFloat(m[1] || "0");
  const u = (m[2] || "").toLowerCase();
  if(u === "k") v *= 1e3;
  else if(u === "m") v *= 1e6;
  else if(m[2] === "万") v *= 1e4;
  return Math.round(v) || 0;
}

(async()=>{
  const reportDay = process.env.REPORT_DAY || "";
  const b = await puppeteer.connect({browserURL:"http://localhost:44407"});
  const page = await b.newPage();
  const raw = JSON.parse(fs.readFileSync("/root/x_cookies.json","utf8"));
  for (const c of raw){
    await page.setCookie({
      name:c.name,value:c.value,domain:c.domain,path:c.path||"/",
      httpOnly:!!c.httpOnly,secure:!!c.secure,
      ...(c.expirationDate?{expires:Math.floor(c.expirationDate)}:{})
    });
  }

  await page.goto("https://x.com/home",{waitUntil:"domcontentloaded",timeout:45000});
  await new Promise(r=>setTimeout(r,3500));

  const scrapeCurrent = async (reportDayArg) => await page.evaluate((reportDayArg)=>{
    const parseN=(s)=>{
      if(!s) return 0;
      const m=String(s).replace(/,/g,"").match(/([\d.]+)\s*([KkMm万]?)/);
      if(!m) return 0;
      let v=parseFloat(m[1]||"0");
      const u=(m[2]||"").toLowerCase();
      if(u==="k") v*=1e3;
      else if(u==="m") v*=1e6;
      else if(m[2]==="万") v*=1e4;
      return Math.round(v)||0;
    };

    const rows=[];
    document.querySelectorAll('article[data-testid="tweet"]').forEach(a=>{
      const txt=(a.querySelector('[data-testid="tweetText"]')?.textContent||"").trim().replace(/\s+/g," ").slice(0,140);
      const dt=a.querySelector("time")?.getAttribute("datetime")||"N/A";

      const getByTestid=(k)=>{
        const e=[...a.querySelectorAll("[data-testid]")].find(x=>(x.getAttribute("data-testid")||"").includes(k));
        const s=e?(e.getAttribute("aria-label")||e.textContent||"0"):"0";
        return parseN(s);
      };

      const replies=getByTestid("reply");
      const retweets=getByTestid("retweet");
      const likes=getByTestid("like");
      const bookmarks=getByTestid("bookmark");
      const vEl=a.querySelector('a[href*="/analytics"]');
      const impressions=parseN(vEl?.textContent||"0");

      const full=(a.innerText||"");
      const isReply=/(Replying to|回复|回覆)/i.test(full);
      const statusLink = [...a.querySelectorAll('a[href*="/status/"]')].find(x=>x.querySelector('time'));
      const url = statusLink ? statusLink.href : '';
      let day = '';
      if (dt && dt !== 'N/A') {
        try { day = new Date(dt).toLocaleDateString('en-CA', {timeZone:'Asia/Shanghai'}); } catch(e) {}
      }
      if (reportDayArg && day && day !== reportDayArg) return;
      rows.push({date:dt,day,url,content:txt||"(no text)",replies,retweets,likes,impressions,bookmarks,isReply});
    });
    return rows;
  }, reportDayArg);

  const loadAndScrape = async (url) => {
    await page.goto(url,{waitUntil:"domcontentloaded",timeout:50000});
    await new Promise(r=>setTimeout(r,3500));
    for(let i=0;i<4;i++){ await page.evaluate(()=>window.scrollBy(0,2200)); await new Promise(r=>setTimeout(r,1800)); }
    return await scrapeCurrent(reportDay);
  };

  // 按用户要求：all(总), posts(主帖), replies(回复)
  let allRows = await loadAndScrape("https://x.com/i/account_analytics/content?type=all&sort=impressions&dir=desc&days=1");
  let posts = await loadAndScrape("https://x.com/i/account_analytics/content?type=posts&sort=impressions&dir=desc&days=1");
  let replyRows = await loadAndScrape("https://x.com/i/account_analytics/content?type=replies&sort=impressions&dir=desc&days=1");

  // Fallback: analytics tabs empty -> use profile/with_replies to avoid all-zero
  if (!posts.length && !allRows.length && !replyRows.length) {
    let profileHref = await page.evaluate(()=>{
      const a=document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
      return a ? a.getAttribute("href") : "";
    });
    if(!profileHref || !profileHref.startsWith("/")) profileHref = "/home";
    const profileUrl = profileHref === "/home" ? "https://x.com/home" : ("https://x.com" + profileHref);

    posts = await loadAndScrape(profileUrl);
    const withReplies = profileHref === "/home" ? "https://x.com/home" : ("https://x.com" + profileHref + "/with_replies");
    replyRows = await loadAndScrape(withReplies);
    allRows = posts.concat(replyRows);
  }

  const sum=(arr,k)=>arr.reduce((n,p)=>n+(Number(p[k])||0),0);

  const postImpressions=sum(posts,"impressions");
  const replyImpressions=sum(replyRows,"impressions");
  const allImpressions=sum(allRows,"impressions");
  const totalImpressions=allImpressions>0 ? allImpressions : (postImpressions+replyImpressions);
  const likes=sum(posts,"likes");
  const replies=sum(posts,"replies");
  const reposts=sum(posts,"retweets");
  const bookmarks=sum(posts,"bookmarks");
  const engagements=likes+replies+reposts+bookmarks;
  const er=totalImpressions>0?((engagements/totalImpressions)*100):0;

  const repliesTop = replyRows.sort((a,b)=>(b.impressions||0)-(a.impressions||0)).slice(0,10);

  const data = {
    overview:{
      impressions:String(postImpressions),
      replyImpressions:String(replyImpressions),
      totalImpressions:String(totalImpressions),
      impressionsDir:"",
      engagementRate:er.toFixed(2)+"%",
      engagementDir:"",
      engagements:String(engagements),
      likes:String(likes),
      replies:String(replies),
      reposts:String(reposts),
      bookmarks:String(bookmarks),
      profileVisits:"N/A",
      followers:"N/A"
    },
    posts:posts.slice(0,30),
    replies_top10:repliesTop,
    replies_posts:allRows.slice(0,20)
  };

  console.log(JSON.stringify(data));
  await page.close();
  await b.disconnect();
})().catch(e=>{
  console.error(e.message);
  console.log(JSON.stringify({overview:{impressions:"0",engagementRate:"0%",engagements:"0",likes:"0",replies:"0",reposts:"0",bookmarks:"0",profileVisits:"N/A",followers:"N/A"},posts:[]}));
});
NODE

ANALYTICS_JSON=$(NODE_PATH=/tmp/node_modules timeout 150 node /tmp/x_daily_analytics.js 2>/dev/null | grep '^{' | tail -1 || echo '{"overview":{"impressions":"0","engagementRate":"0%","engagements":"0","likes":"0","replies":"0","reposts":"0","bookmarks":"0","profileVisits":"N/A","followers":"N/A"},"posts":[]}')

# 2) Reply stats
REPLY_STATS=$(python3 - <<'PYEND'
import json, time, os
log_path="/root/.openclaw/workspace/data/x_reply_log.jsonl"
now=int(time.time())
start=now-86400
lines=[]
if os.path.exists(log_path):
    for line in open(log_path,"r",encoding="utf-8",errors="ignore"):
        line=line.strip()
        if not line:continue
        try:
            obj=json.loads(line)
            if obj.get("ts",0)>=start:lines.append(obj)
        except:pass
total=len(lines)
by_source={}
for l in lines:
    s=l.get("source","other")
    by_source[s]=by_source.get(s,0)+1
samples=[{"handle":l.get("handle","?"),"reply":l.get("reply_text","")[:80],"source":l.get("source","?")} for l in lines[-8:]]
print(json.dumps({"total":total,"by_source":by_source,"samples":samples},ensure_ascii=False))
PYEND
)

# 3) Send to agent for Discord components v2 formatting
openclaw agent \
  --session-id x-daily-report \
  --thinking minimal \
  --deliver \
  --reply-channel discord \
  --reply-to "channel:1476191544808837192" \
  --message "
你是大帅的推特运营助手小虾🦐，生成日报并用 message tool 发送 Discord components v2。

## 真实数据

### 系统状态
时间：$NOW
主机：$HOST
运行时长：$UPTIME_LINE
负载(1/5/15)：$LOAD_LINE
内存：$MEM_SUMMARY
磁盘：$DISK_SUMMARY
上海天气：$WEATHER

### Analytics 概览 + 每条推文曝光
$ANALYTICS_JSON

### 昨日回复统计
$REPLY_STATS

## 发送要求

调用 message tool：action=send, channel=discord, to=channel:1476191544808837192

使用 components 字段，格式：
{
  \"blocks\": [...],
  \"container\": {\"accentColor\": \"#1DA1F2\"}
}

## 内容分区（每个用 {\"type\":\"text\",\"text\":\"...\"} block，分区间用 {\"type\":\"separator\"}）

**第1区：标题**
type=heading, text=📊 系统 + X 日报 | $(TZ=Asia/Shanghai date +%Y-%m-%d)

**第2区：🖥️ 系统快照**
主机/运行时长/负载/内存/磁盘/上海天气，6行内，紧凑展示。

**第3区：📈 昨日概览（仅昨天）**
用 emoji 列出 overview 数据（必须同时展示）：
👁 Post曝光 XX ｜ 💬 Reply曝光 XX ｜ Σ总曝光 XX
❤️ 赞 XX ｜🔁 转 XX ｜💬 评 XX ｜📖 收藏 XX
📊 互动率 XX% ｜👤 主页访问 XX
数值统一短格式：1000=>1K，12000=>1.2W，950000=>95W

**第4区：🔥 Post曝光 TOP 10（昨日）**
从 posts 按 impressions 降序取前10，每行：
序号. 内容前40字… ｜👁 XX ｜❤️ XX ｜🔁 XX ｜💬 XX（下一行附链接）

**第5区：💬 Reply曝光 TOP 10（昨日）**
从 replies_top10 按 impressions 降序取前10，每行：
序号. 回复前40字… ｜👁 XX ｜❤️ XX ｜🔁 XX ｜💬 XX（下一行附链接）

**第6区：🧠 低曝光诊断 + 立即执行**
- 找出曝光最低的3条（post/reply都可）
- 给出3条可执行改进（必须具体到“改哪个脚本/提示词哪一条”）
- 并在文末附“建议变更清单”（仅给出具体可执行项，不要写权限/授权阻塞话术）

**第7区：📌 今天动作**
3条可执行建议，≤35字，带 ✅

**页脚**
-# 🦐 小虾自动生成 | $(TZ=Asia/Shanghai date '+%H:%M')

## 规则
- 用真实数据，不要编造
- 简洁有力，不废话

- Reply曝光TOP10 必须来自 replies_top10；若不足10条，明确写“仅N条（昨日）”，并逐条给出链接。
- 若某条文本过长，允许截断文本，但链接必须完整可点击。
- 发送后回复 NO_REPLY
"
