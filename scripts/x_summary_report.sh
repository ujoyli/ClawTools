#!/usr/bin/env bash
# Every 30 mins: Summarize replies and engagement
set -uo pipefail
WORKDIR="/root/.openclaw/workspace"
LOG_FILE="$WORKDIR/data/x_reply_log.jsonl"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "还没有发出去的回复记录。"
  exit 0
fi

COUNT=$(wc -l < "$LOG_FILE")
RECENT=$(tail -n 10 "$LOG_FILE")

# Compute views for last N targets (best-effort)
VIEWS_REPORT=$(python3 - <<'PY'
import os, json, subprocess, re
log_path='/root/.openclaw/workspace/data/x_reply_log.jsonl'
if not os.path.exists(log_path):
    print('')
    raise SystemExit
# take last 5 targets for sampling
lines=[]
for line in open(log_path,'r',encoding='utf-8',errors='ignore'):
    if line.strip():
        lines.append(line)
last=lines[-5:]
urls=[]
for l in last:
    try:
        obj=json.loads(l)
        u=obj.get('target_url','')
        if u: urls.append(u)
    except: pass
urls=list(dict.fromkeys(urls))[:3]
out=[]
for u in urls:
    try:
        r=subprocess.check_output(['node','/root/.openclaw/workspace/scripts/x_get_views.js',u,'--port','18802'], env={**os.environ,'NODE_PATH':'/tmp/node_modules'}, timeout=120)
        obj=json.loads(r.decode('utf-8','ignore'))
        if obj.get('ok'):
            out.append(f"- {u} views≈{obj.get('views')}")
        else:
            out.append(f"- {u} views=NA")
    except Exception:
        out.append(f"- {u} views=NA")
print('\n'.join(out))
PY
)

# Use agent to summarize
openclaw agent --session-id x-summary --thinking minimal --deliver --reply-channel discord --reply-to "channel:1476191544808837192" --message "这是最近半小时的推特回复日志（最多10条）：
$RECENT

半小时内发送总数（累计行数）：$COUNT

抽查曝光量（views，近似）：
${VIEWS_REPORT}

请用极简格式输出：
1) 本半小时做了什么（3条以内）
2) 抽查曝光量
3) 如果曝光量无法获取，说明原因和下一步修复动作"
