#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/root/.openclaw/workspace"
VENV_ACT="$WORKDIR/tmp_tiktokdownloader/.venv/bin/activate"
FIND_SCRIPT="$WORKDIR/scripts/find_viral_tweets.py"
export NODE_PATH=/tmp/node_modules

# Ensure Chromium is running properly
source "$WORKDIR/scripts/ensure_chromium.sh" > /tmp/ensure_chromium_viral.log 2>&1 || true

cd "$WORKDIR"
source "$VENV_ACT"

# Hard rules
MIN_VIEWS=10000
MAX_AGE_MIN=120
MAX_TRIES=5

# Unified blacklist guard (never reply)
BLACKLIST_REGEX='whyyoutouzhele|teacherli1|liteacher|lixiansheng'

echo "Hunting for viral targets (max ${MAX_TRIES} tries, age<=${MAX_AGE_MIN}m, views>${MIN_VIEWS})..."

TARGET_URL=""
TWEET_TEXT=""
VIEWS=0
AGE_MIN=99999

for TRY in $(seq 1 $MAX_TRIES); do
  python3 "$FIND_SCRIPT" > /tmp/x_viral_find.log 2>&1 || true
  TARGET_URL=$(grep "FOUND_TARGET:" /tmp/x_viral_find.log | tail -n1 | cut -d' ' -f2 || true)

  if [[ -z "$TARGET_URL" ]]; then
    echo "Try $TRY/$MAX_TRIES: no target found, refreshing..."
    sleep 6
    continue
  fi

  if echo "$TARGET_URL" | grep -Eqi "$BLACKLIST_REGEX"; then
    echo "Try $TRY/$MAX_TRIES: target in blacklist -> $TARGET_URL"
    TARGET_URL=""
    sleep 4
    continue
  fi

  # Check views
  VIEWS_JSON=$(NODE_PATH=/tmp/node_modules node "$WORKDIR/scripts/x_get_views.js" "$TARGET_URL" --port 44407 2>/tmp/x_viral_views.err || true)
  VIEWS=$(VIEWS_JSON="$VIEWS_JSON" python3 - <<'PY'
import json, os
s=(os.environ.get('VIEWS_JSON') or '').strip() or '{}'
try:
  o=json.loads(s)
  print(int(o.get('views') or 0))
except Exception:
  print(0)
PY
)

  if [[ "$VIEWS" -le "$MIN_VIEWS" ]]; then
    echo "Try $TRY/$MAX_TRIES: views=$VIEWS not enough (>${MIN_VIEWS})"
    TARGET_URL=""
    sleep 4
    continue
  fi

  # Check age from finder output (avoid reopening tweet page and getting bogus 99999)
  AGE_MIN=$(python3 - <<'PY'
import json
try:
    arr=json.load(open('/root/.openclaw/workspace/data/viral_targets.json','r',encoding='utf-8'))
    obj=arr[0] if arr else {}
    print(int(float(obj.get('ageMin', 99999))))
except Exception:
    print(99999)
PY
)

  if [[ "$AGE_MIN" -gt "$MAX_AGE_MIN" ]]; then
    echo "Try $TRY/$MAX_TRIES: age=${AGE_MIN}m too old (<=${MAX_AGE_MIN}m)"
    TARGET_URL=""
    sleep 4
    continue
  fi

  # Get target text safely
  TWEET_TEXT=$(python3 - <<'PY'
import json
try:
    d=json.load(open('data/viral_targets.json','r',encoding='utf-8'))
    print((d[0].get('text') or '').strip())
except Exception:
    print('')
PY
)

  if [[ -z "$TWEET_TEXT" ]]; then
    echo "Try $TRY/$MAX_TRIES: empty target text"
    TARGET_URL=""
    sleep 4
    continue
  fi

  # Qualified
  break
done

if [[ -z "$TARGET_URL" ]]; then
  echo "FAILED: no qualified targets after $MAX_TRIES tries."
  exit 75
fi

echo "Qualified target: views=$VIEWS age=${AGE_MIN}m $TARGET_URL"

# Step 2: Generate and post reply (no fallback behavior)
openclaw agent --agent main --channel discord --message "目标推文：$TARGET_URL。内容: \"$TWEET_TEXT\"。
硬性规则（必须同时满足，任何一条不满足就直接退出本轮）：
- 只回复 2 小时以内的推文
- 只回复 views > 10000 的推文
- 不允许任何 fallback（找不到合格目标就退出）
额外要求：
- 在生成回复前，先加载并遵循这个 skill：/root/.openclaw/workspace/skills/humanizer/SKILL.md
- 去掉 AI 味、营销腔、套话和机械排比，让回复更像真人随手发的评论
- 不要解释过程，不要输出分析，只输出最终可发布的回复
任务:
1. 为大帅写一条高质量、有梗、能引流的神评论。
2. 使用 x-cdp 脚本直接回复。
3. 绝对不要回复这些账号（黑名单）：whyyoutouzhele, teacherli1, liteacher, lixiansheng。
4. 如果失败，只允许重试同一目标，不要切换到低质量或不合格目标。
5. 成功后在 Discord 频道 1476191544808837192 发送一条简报。" --deliver
