#!/bin/bash

CONFIG_FILE="/root/.openclaw/cron/jobs.json"

# 备份原文件
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

# 修复所有 delivery.channel 为 "last" 的任务，改为 "discord"
jq '
.jobs |= map(
  if .delivery.channel == "last" then
    .delivery.channel = "discord"
  else
    .
  end
)
' "$CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$CONFIG_FILE"

echo "已修复所有定时任务的 delivery.channel 设置为 discord"
