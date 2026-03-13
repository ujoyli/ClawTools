#!/usr/bin/env bash
set -euo pipefail

# Daily morning system report (load/process/disk/mem + Shanghai weather)
# Sends to the current Discord DM via OpenClaw CLI.

TARGET_DISCORD_ID="1476191544808837192"  # DM channel id

now=$(date '+%Y-%m-%d %H:%M:%S %Z')
host=$(hostname)

uptime_line=$(uptime -p 2>/dev/null || true)
load_line=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}')

mem=$(free -h 2>/dev/null || true)
disk=$(df -h -x tmpfs -x devtmpfs 2>/dev/null || true)

# Top processes
cpu_top=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 10)
mem_top=$(ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 10)

# Optional: OpenClaw gateway status (best-effort)
claw_status=$(openclaw gateway status 2>/dev/null | head -n 20 || true)

# Shanghai weather (metric, compact)
weather=$(curl -s "wttr.in/Shanghai?format=%l:+%c+%t+%h+%w" 2>/dev/null || true)

msg=$(cat <<EOF
【早报】$now
主机：$host
运行时长：${uptime_line:-N/A}
负载(1/5/15)：${load_line:-N/A}

上海天气：${weather:-N/A}

内存：
$mem

磁盘：
$disk

Top CPU：
$cpu_top

Top MEM：
$mem_top

OpenClaw：
${claw_status:-N/A}
EOF
)

# Send (silent to avoid noisy notifications; adjust if you want)
openclaw message send \
  --channel discord \
  --target "$TARGET_DISCORD_ID" \
  --message "$msg" \
  --silent \
  --json >/dev/null
