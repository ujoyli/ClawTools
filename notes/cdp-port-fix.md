# CDP 端口固定修复记录

**日期**: 2026-03-01  
**问题**: CDP 端口随机分配，导致评论脚本连接不稳定  
**解决方案**: 固定 CDP 端口为 `44407`

## 修复内容

### 1. 更新 cdp-utils.js 默认端口
文件：`/root/.openclaw/workspace/skills/x-cdp/scripts/lib/cdp-utils.js`
```javascript
const DEFAULT_PORT = 44407;  // 已固定
```

### 2. 更新 browserwing 配置
文件：`/home/browserwing/config.toml`
```toml
[browser]
bin_path = '/usr/bin/chromium'
user_data_dir = './chrome_user_data'
control_url = ''  # 空值，使用本地模式
extra_args = ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu', '--disable-setuid-sandbox', '--disable-extensions', '--remote-debugging-port=44407']
```

### 3. 修复评论脚本端口
以下脚本已更新为使用 `--port 44407`：

- ✅ `/root/.openclaw/workspace/scripts/x_viral_fast_reply.sh`
- ✅ `/root/.openclaw/workspace/scripts/x_viral_sopilot_reply.sh`
- ✅ `/root/.openclaw/workspace/scripts/douyin_post_next_video_unlimited.sh`
- ✅ `/root/.openclaw/workspace/scripts/rebang_home_hot_image_tweet_unlimited.sh`

### 4. 更新 ensure_chromium.sh
文件：`/root/.openclaw/workspace/scripts/ensure_chromium.sh`
- 添加 `CDP_PORT=44407` 变量
- 增加 CDP 端口健康检查
- 如果端口未响应，自动启动 Chromium

## 验证结果

```bash
# 检查 CDP 端口
curl -s http://localhost:44407/json/version
# ✅ 返回浏览器信息

# 运行确保脚本
bash scripts/ensure_chromium.sh
# ✅ CDP port 44407 is responding
```

## 使用说明

### 手动启动 Chromium（如需要）
```bash
nohup chromium --remote-debugging-port=44407 \
  --user-data-dir=/home/browserwing/chrome_user_data \
  --no-first-run --no-default-browser-check \
  --no-sandbox --disable-dev-shm-usage --disable-gpu \
  > /tmp/chromium_44407.log 2>&1 &
```

### 测试连接
```bash
cd /root/.openclaw/workspace/skills/x-cdp
NODE_PATH=/tmp/node_modules node scripts/setup.js --port 44407 --profile /home/browserwing/chrome_user_data
```

### 测试评论功能
```bash
NODE_PATH=/tmp/node_modules node scripts/reply-tweet.js \
  "https://x.com/xxx/status/123" "测试评论" --port 44407 --dry-run
```

## 注意事项

1. **端口统一**: 所有 X-CDP 相关脚本现在都使用 `44407` 端口
2. **进程管理**: 使用 `ensure_chromium.sh` 定期检查，避免进程过多
3. **Profile 隔离**: 继续使用 `/home/browserwing/chrome_user_data` 保存登录状态
4. **Legacy 脚本**: `x_viral_fast_reply_legacy.sh` 仍使用 18802，如需使用请手动修改

## 相关文件

- 主配置：`/home/browserwing/config.toml`
- CDP 工具库：`/root/.openclaw/workspace/skills/x-cdp/scripts/lib/cdp-utils.js`
- 健康检查：`/root/.openclaw/workspace/scripts/ensure_chromium.sh`
- 评论脚本：`/root/.openclaw/workspace/scripts/x_viral_fast_reply.sh`
