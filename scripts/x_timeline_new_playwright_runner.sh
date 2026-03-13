#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
SCRIPT="$WORKDIR/scripts/x_timeline_new_playwright.sh"
CHANNEL_ID="1476191544808837192"

# Use flock to prevent concurrent executions
# But first, check for stale lock (older than 30 minutes)
LOCK_FILE="/tmp/x_timeline_new_playwright_runner.lock"
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
  if [[ $LOCK_AGE -gt 1800 ]]; then
    echo "[runner] Removing stale lock file (age: ${LOCK_AGE}s)"
    rm -f "$LOCK_FILE"
  fi
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another instance is already running, exiting"
  exit 0
fi

# random delay 0-1 min
DELAY=${RANDOM_DELAY_MIN:-$((RANDOM % 2))}
echo "[runner] random delay ${DELAY}m"
sleep "${DELAY}m"

OUT_FILE="/tmp/x_timeline_new_runner_$(date +%s).log"
set +e
# Add 20 min timeout for the actual script execution
timeout 1200 bash "$SCRIPT" >"$OUT_FILE" 2>&1
RC=$?
if [[ $RC -eq 124 ]]; then
  echo "Script timed out after 20 minutes" >> "$OUT_FILE"
fi

# Defense-in-depth: enforce hard filter at runner level too
# require age<=120m and views>5000; otherwise treat as skipped round
if [[ -f /tmp/x_timeline_new_pw_pick.json ]]; then
  FILTER_OK=$(python3 - <<'PY'
import json
p='/tmp/x_timeline_new_pw_pick.json'
try:
  d=json.load(open(p,'r',encoding='utf-8'))
  # Skip if pick failed (ok=false)
  if not d.get('ok', False):
    print('skip')
    exit(0)
  age=float(d.get('ageMin',99999))
  views=int(d.get('views',0))
  print('1' if (age<=120 and views>10000) else '0')
except Exception:
  print('0')
PY
)
  if [[ "$FILTER_OK" == "skip" ]]; then
    echo "Runner: no suitable target found, skip this round" >> "$OUT_FILE"
    RC=75
  elif [[ "$FILTER_OK" != "1" ]]; then
    echo "Runner hard filter hit: skip this round (age/views not qualified)" >> "$OUT_FILE"
    RC=75
  fi
fi

# Extract Target and Reply (grep may return empty, that's OK)
TARGET=$(grep -E '^Target:' "$OUT_FILE" 2>/dev/null | tail -n1 | sed 's/^Target: //' || true)
REPLY=$(grep -E '^Reply:' "$OUT_FILE" 2>/dev/null | tail -n1 | sed 's/^Reply: //' || true)

if [[ $RC -eq 0 ]]; then
  MSG="✅ 脚本: x_timeline_new_playwright.sh\nTarget: ${TARGET:-N/A}\nReply: ${REPLY:-N/A}"
elif [[ $RC -eq 75 ]]; then
  LAST=$(tail -n 6 "$OUT_FILE" | sed ':a;N;$!ba;s/\n/ | /g')
  MSG="⏭️ 脚本: x_timeline_new_playwright.sh\n本轮跳过（未命中过滤规则：2小时内 + views>10000）\n日志: ${LAST}"
else
  LAST=$(tail -n 8 "$OUT_FILE" | sed ':a;N;$!ba;s/\n/ | /g')
  MSG="❌ 脚本: x_timeline_new_playwright.sh\n退出码: $RC\nTarget: ${TARGET:-N/A}\nReply: ${REPLY:-N/A}\n日志尾部: ${LAST}"
fi

openclaw message send --channel discord --target "channel:${CHANNEL_ID}" --message "$MSG" >/dev/null 2>&1 || true

exit $RC
