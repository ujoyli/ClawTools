#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/root/.openclaw/workspace"
SCRIPT="$WORKDIR/scripts/x_timeline_new_playwright.sh"
CHANNEL_ID="1476191544808837192"

# random delay 0-1 min, with base schedule every 11 min => effective 11~12 min
DELAY=${RANDOM_DELAY_MIN:-$((RANDOM % 2))}
echo "[runner] random delay ${DELAY}m"
sleep "${DELAY}m"

OUT_FILE="/tmp/x_timeline_new_runner_$(date +%s).log"
set +e
# Add 15 min timeout for the actual script execution
timeout 900 bash "$SCRIPT" >"$OUT_FILE" 2>&1
RC=$?
if [[ $RC -eq 124 ]]; then
  echo "Script timed out after 15 minutes" >> "$OUT_FILE"
fi

# Extract Target and Reply (grep may return empty, that's OK)
TARGET=$(grep -E '^Target:' "$OUT_FILE" 2>/dev/null | tail -n1 | sed 's/^Target: //' || true)
REPLY=$(grep -E '^Reply:' "$OUT_FILE" 2>/dev/null | tail -n1 | sed 's/^Reply: //' || true)

if [[ $RC -eq 0 ]]; then
  MSG="✅ 脚本: x_timeline_new_playwright.sh\nTarget: ${TARGET:-N/A}\nReply: ${REPLY:-N/A}"
else
  LAST=$(tail -n 8 "$OUT_FILE" | sed ':a;N;$!ba;s/\n/ | /g')
  MSG="❌ 脚本: x_timeline_new_playwright.sh\n退出码: $RC\nTarget: ${TARGET:-N/A}\nReply: ${REPLY:-N/A}\n日志尾部: ${LAST}"
fi

openclaw message send --channel discord --target "channel:${CHANNEL_ID}" --message "$MSG" >/dev/null 2>&1 || true

exit $RC
