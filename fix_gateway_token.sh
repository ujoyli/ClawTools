#!/bin/bash

CONFIG_FILE="/root/.openclaw/openclaw.json"

# 恢复原始 token 并添加 remote.token
jq '.gateway.auth.token = "5109a58b684d143d4c4c8bee84bef9f402b790cf0e52a333" | .gateway.remote.token = "5109a58b684d143d4c4c8bee84bef9f402b790cf0e52a333"' "$CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$CONFIG_FILE"

echo "Gateway token 已修复：auth.token 和 remote.token 已设置为相同值"
