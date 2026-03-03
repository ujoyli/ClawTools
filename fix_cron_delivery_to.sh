#!/bin/bash

CONFIG_FILE="/root/.openclaw/cron/jobs.json"

# 备份原文件
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

# 修复 delivery.to 字段，确保格式为 "channel:xxxxx"
jq '
.jobs |= map(
  if .delivery.to and (.delivery.to | startswith("channel:") | not) then
    .delivery.to = "channel:" + (.delivery.to | tostring)
  else
    .
  end
)
' "$CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$CONFIG_FILE"

echo "已修复所有定时任务的 delivery.to 格式"
