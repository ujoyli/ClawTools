#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
export NODE_PATH=/tmp/node_modules

# ensure browser/CDP
source "$WORKDIR/scripts/ensure_chromium.sh" >/tmp/ensure_chromium_test_report.log 2>&1 || true
bash "$WORKDIR/tmp/start_chromium.sh" >/tmp/start_chromium_test_report.log 2>&1 || true

cat >/tmp/x_report_fetch_test.js <<'NODE'
const puppeteer = require('puppeteer-core');
const fs = require('fs');

function parseNum(x){
  if(!x) return 0;
  const m = String(x).replace(/,/g,'').match(/([\d.]+)\s*([KkMm万]?)/);
  if(!m) return 0;
  let v = parseFloat(m[1] || '0');
  const u = (m[2] || '').toLowerCase();
  if(u==='k') v*=1e3;
  else if(u==='m') v*=1e6;
  else if(m[2]==='万') v*=1e4;
  return Math.round(v) || 0;
}

(async()=>{
  const b = await puppeteer.connect({browserURL:'http://localhost:44407'});
  const page = await b.newPage();
  const raw = JSON.parse(fs.readFileSync('/root/x_cookies.json','utf8'));
  for (const c of raw){
    await page.setCookie({
      name:c.name,value:c.value,domain:c.domain,path:c.path||'/',
      httpOnly:!!c.httpOnly,secure:!!c.secure,
      ...(c.expirationDate?{expires:Math.floor(c.expirationDate)}:{})
    });
  }

  await page.goto('https://x.com/home',{waitUntil:'domcontentloaded',timeout:45000});
  await new Promise(r=>setTimeout(r,4000));

  let profileHref = await page.evaluate(()=>{
    const a=document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
    return a ? a.getAttribute('href') : '';
  });
  if(!profileHref || !profileHref.startsWith('/')) profileHref='/home';
  const profileUrl = profileHref==='/home' ? 'https://x.com/home' : ('https://x.com'+profileHref);

  await page.goto(profileUrl,{waitUntil:'domcontentloaded',timeout:45000});
  await new Promise(r=>setTimeout(r,3500));
  for(let i=0;i<4;i++){ await page.evaluate(()=>window.scrollBy(0,2200)); await new Promise(r=>setTimeout(r,1800)); }

  const data = await page.evaluate(()=>{
    const parseN=(s)=>{ if(!s) return 0; const m=String(s).replace(/,/g,'').match(/([\d.]+)\s*([KkMm万]?)/); if(!m) return 0; let v=parseFloat(m[1]||'0'); const u=(m[2]||'').toLowerCase(); if(u==='k') v*=1e3; else if(u==='m') v*=1e6; else if(m[2]==='万') v*=1e4; return Math.round(v)||0; };
    const now=Date.now(), maxAge=7*24*3600*1000;
    const posts=[];
    document.querySelectorAll('article[data-testid="tweet"]').forEach(a=>{
      const txt=(a.querySelector('[data-testid="tweetText"]')?.textContent||'').trim().replace(/\s+/g,' ').slice(0,140);
      const dt=a.querySelector('time')?.getAttribute('datetime')||'';
      let ageOk=true;
      if(dt){ const t=new Date(dt).getTime(); if(Number.isFinite(t)) ageOk=(now-t)<=maxAge; }
      if(!ageOk) return;
      const getBy=(k)=>{ const e=[...a.querySelectorAll('[data-testid]')].find(x=>(x.getAttribute('data-testid')||'').includes(k)); const s=e?(e.getAttribute('aria-label')||e.textContent||'0'):'0'; return parseN(s); };
      const replies=getBy('reply'), retweets=getBy('retweet'), likes=getBy('like'), bookmarks=getBy('bookmark');
      const vEl=a.querySelector('a[href*="/analytics"]');
      const impressions=parseN(vEl?.textContent||'0');
      posts.push({date:dt||'N/A',content:txt||'(no text)',replies,retweets,likes,impressions,bookmarks});
    });
    const sum=(k)=>posts.reduce((n,p)=>n+(Number(p[k])||0),0);
    const impressions=sum('impressions'), likes=sum('likes'), replies=sum('replies'), reposts=sum('retweets'), bookmarks=sum('bookmarks');
    const engagements=likes+replies+reposts+bookmarks;
    const er=impressions>0?((engagements/impressions)*100):0;
    return {overview:{impressions,engagements,engagementRate:Number(er.toFixed(2)),likes,replies,reposts,bookmarks}, posts:posts.slice(0,30)};
  });

  fs.writeFileSync('/root/.openclaw/workspace/tmp/x_report_fetch_test.json', JSON.stringify(data,null,2));
  console.log(JSON.stringify({ok:true,impressions:data.overview.impressions,posts:data.posts.length}));
  await page.close();
  await b.disconnect();
})();
NODE

NODE_PATH=/tmp/node_modules timeout 180 node /tmp/x_report_fetch_test.js | tee /tmp/x_report_fetch_test.log
