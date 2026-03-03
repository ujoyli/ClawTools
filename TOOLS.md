# TOOLS.md - Tool Configuration & Notes

> Document tool-specific configurations, gotchas, and credentials here.

---

## Credentials Location

All credentials stored in `.credentials/` (gitignored):
- `example-api.txt` — Example API key

---

## X (Twitter) CDP Automation

**Status:** ✅ Working

**Configuration:**
- BrowserWing Web UI: http://localhost:18080 (management interface only)
- Chromium CDP port: 44407 (actual browser control)

**Gotchas:**
- Scripts must use CDP port 44407, NOT 18080
- 18080 is only for BrowserWing Web UI, returns HTML not CDP JSON
- x_bigv_monitor.sh and ensure_x_cookie.sh updated to use 44407 (2026-03-03)
- If Chromium is not responding, check `ps aux | grep -i chrom`

**Common Operations:**
```bash
# Check BrowserWing health
curl http://localhost:18080/health

# Run Big V monitor manually
bash scripts/x_bigv_monitor.sh
```

---

## X (Twitter) Automation - x-cdp

**Status:** ⚠️ Issues - Login session unstable

**Configuration:**
- Browserwing CDP session on port 18802
- Requires active Chromium session with Twitter login

**Gotchas:**
- Browserwing 会话经常丢失登录状态，导致发送按钮被禁用
- 今天已发生 3 次登录问题失败 (2026-03-01)
- 需要配置 Twitter Cookie 或定期重新建立登录会话

**Workaround:**
1. 检查 Chromium 登录状态：`ps aux | grep -i chrom | grep -v grep`
2. 如需重新登录，手动打开浏览器登录 Twitter
3. 考虑导出 Cookie 用于自动化（参考 bilibili-cookie-download skill 模式）

---

## What Goes Here

- Tool configurations and settings
- Credential locations (not the credentials themselves!)
- Gotchas and workarounds discovered
- Common commands and patterns
- Integration notes

## Why Separate?

Skills define *how* tools work. This file is for *your* specifics — the stuff that's unique to your setup.

---

*Add whatever helps you do your job. This is your cheat sheet.*
