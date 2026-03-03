#!/usr/bin/env bash
set -uo pipefail

WORKDIR="/root/.openclaw/workspace"
VENV_ACT="$WORKDIR/tmp_tiktokdownloader/.venv/bin/activate"
FIND_SCRIPT="$WORKDIR/scripts/find_viral_tweets.py"
export NODE_PATH=/tmp/node_modules

# Ensure Chromium is running properly
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_viral.log 2>&1 || true

cd "$WORKDIR"
source "$VENV_ACT"

# Step 1: Find viral targets with retries
echo "Hunting for viral targets..."
MAX_TRIES=3
TRY=1
while [ $TRY -le $MAX_TRIES ]; do
  python3 "$FIND_SCRIPT" > /tmp/x_viral_find.log 2>&1
  TARGET_URL=$(grep "FOUND_TARGET:" /tmp/x_viral_find.log | cut -d' ' -f2 || true)
  if [[ -n "$TARGET_URL" ]]; then break; fi
  echo "Try $TRY failed to find targets. Retrying in 10s..."
  sleep 10
  TRY=$((TRY+1))
done

if [[ -z "$TARGET_URL" ]]; then
    echo "FAILED: No targets found after $MAX_TRIES tries."
    exit 75  # EX_TEMPFAIL - no action taken, don't notify
fi

# Unified blacklist guard (never reply)
BLACKLIST_REGEX='whyyoutouzhele|teacherli1|liteacher|lixiansheng'
if echo "$TARGET_URL" | grep -Eqi "$BLACKLIST_REGEX"; then
    echo "SKIP: target in blacklist -> $TARGET_URL"
    exit 75
fi

TWEET_TEXT=$(python3 -c "import json; print(json.load(open('data/viral_targets.json'))[0]['text'])")

# Step 2: Use a one-shot agent run to generate AND post the reply autonomously
# We pass the instruction to handle errors internally.
openclaw agent --agent main --channel discord --message "目标推文：$TARGET_URL。内容: \"$TWEET_TEXT\"。
任务:
1. 为大帅写一条高质量、有梗、能引流的神评论。
2. 使用 x-cdp 脚本直接回复。
3. 绝对不要回复这些账号（黑名单）：whyyoutouzhele, teacherli1, liteacher, lixiansheng。
4. 如果失败，尝试调整选择器或等待重试，直到成功或确认环境故障。
5. 成功后在 Discord 频道 1476191544808837192 发送一条简报。" --deliver
