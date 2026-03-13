# ERRORS

## [ERR-20260226-001] openclaw-cron-gateway-token-mismatch

**Logged**: 2026-02-26T15:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
`openclaw cron list` / `openclaw gateway status` failed with `unauthorized: gateway token mismatch`.

### Error
```
unauthorized: gateway token mismatch (set gateway.remote.token to match gateway.auth.token)
```

### Context
- Gateway was running locally on loopback, but CLI could not authenticate.
- Env had `OPENCLAW_GATEWAY_TOKEN` that did not match `~/.openclaw/openclaw.json` `gateway.auth.token`.

### Suggested Fix
- Ensure a single source of truth for gateway token.
- If env var is set, align `gateway.auth.token` (and `gateway.remote.token` if used) to the same value, then restart gateway.

### Resolution
- **Resolved**: 2026-02-26
- Updated `~/.openclaw/openclaw.json` to set `gateway.auth.token` and `gateway.remote.token` to `OPENCLAW_GATEWAY_TOKEN`.
- Restarted gateway; RPC probe became OK.

### Metadata
- Reproducible: yes
- Related Files: /root/.openclaw/openclaw.json

---

## [ERR-20260226-002] openclaw-cron-run-json-flag

**Logged**: 2026-02-26T15:05:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
Tried `openclaw cron run <id> --json`; CLI rejected option.

### Error
```
error: unknown option '--json'
```

### Context
- `openclaw cron run` does not accept `--json` in this version.

### Suggested Fix
- Use `openclaw cron run --expect-final` and parse stdout, or rely on `cron runs` for history.

### Resolution
- **Resolved**: 2026-02-26
- Confirmed via `openclaw cron run --help`.

### Metadata
- Reproducible: yes

---

## [ERR-20260226-003] dnf-docker-ce-conflict-with-moby

**Logged**: 2026-02-26T15:22:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
Installing `docker-ce` conflicted with AppStream `moby` on OpenCloudOS 9.4.

### Error
```
docker-ce conflicts with docker provided by moby ...
(try to add '--allowerasing' ...)
```

### Context
- Goal: install Docker + compose to deploy TrendRadar.

### Suggested Fix
- Prefer AppStream `moby` + EPOL `docker-compose-plugin` on this distro.

### Resolution
- **Resolved**: 2026-02-26
- Installed: `moby`, `docker-compose-plugin`, `docker-compose`.
- Enabled and started `docker` service.

### Metadata
- Reproducible: yes

---

## [ERR-20260226-004] tool-missing-gh-cli

**Logged**: 2026-02-26T15:20:00+08:00
**Priority**: low
**Status**: pending
**Area**: infra

### Summary
`gh` CLI not installed, so GitHub skill commands failed.

### Error
```
/usr/bin/bash: line 1: gh: command not found
```

### Context
Attempted to inspect repo metadata via `gh repo view`.

### Suggested Fix
Install GitHub CLI (`gh`) if needed, or fall back to `web_fetch`/`git clone`.

### Metadata
- Reproducible: yes

---

## [ERR-20260226-005] tool-missing-python-symlink

**Logged**: 2026-02-26T15:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
Attempted to run `python` but only `python3` exists.

### Error
```
python: command not found
```

### Suggested Fix
Use `python3` explicitly or install a `python` symlink package.

### Resolution
- **Resolved**: 2026-02-26
- Switched to Node-based JSON edit when needed.

### Metadata
- Reproducible: yes

---

## [ERR-20260228-001] rebang_to_tweet-dry-run-exit1

**Logged**: 2026-02-28T01:24:00+08:00
**Priority**: medium
**Status**: pending
**Area**: backend

### Summary
Scheduled command `python scripts/rebang_to_tweet.py --dry-run` exited with code 1 during reminder execution.

### Error
```
/root/.openclaw/workspace/scripts/rebang_to_tweet.py:90: SyntaxWarning: invalid escape sequence '\s'
  keywords = re.sub(r'[？！。，、""''《》\s]+', ' ', title).strip()
EXIT:1
```

### Context
- Command: `source /root/.openclaw/workspace/tmp_tiktokdownloader/.venv/bin/activate && cd /root/.openclaw/workspace && python scripts/rebang_to_tweet.py --dry-run`
- Environment: venv `tmp_tiktokdownloader/.venv`
- Output only showed `SyntaxWarning`, but process returned non-zero.

### Suggested Fix
- Fix regex string escaping at `scripts/rebang_to_tweet.py:90` (prefer raw-safe pattern and quote cleanup).
- Add explicit exception/logging on dry-run failure paths so exit cause is visible.
- Re-run dry-run and verify `EXIT:0`.

### Metadata
- Reproducible: yes
- Related Files: /root/.openclaw/workspace/scripts/rebang_to_tweet.py

---
## [ERR-20260304-001] x_viral_interact_agent-no-targets

**Logged**: 2026-03-04T15:30:00+08:00
**Priority**: medium
**Status**: pending
**Area**: backend

### Summary
`x_viral_interact_agent.sh` failed to find viral targets after all retries and exited with code 75.

### Error
```
Hunting for viral targets...
Try 1 failed to find targets. Retrying in 10s...
Try 2 failed to find targets. Retrying in 10s...
Try 3 failed to find targets. Retrying in 10s...
FAILED: No targets found after 3 tries.
(Command exited with code 75)
```

### Context
- Command: `bash /root/.openclaw/workspace/scripts/x_viral_interact_agent.sh`
- Trigger: cron `x:viral-interact`
- Time: 2026-03-04 15:30 (Asia/Shanghai)

### Suggested Fix
- Verify upstream target discovery source is returning candidates at run time.
- Add fallback query/topic set when primary discovery returns empty.
- Emit diagnostic details (API response size/filter thresholds) per retry.

### Metadata
- Reproducible: unknown
- Related Files: /root/.openclaw/workspace/scripts/x_viral_interact_agent.sh

---

---

## [ERR-20260306-001] x-timeline-agent-generates-status-report-instead-of-reply

**Logged**: 2026-03-06T10:20:00+08:00
**Priority**: critical
**Status**: open
**Area**: automation/x-cdp

### Summary
The `x_timeline_new_playwright.sh` script's AI agent step generates a system status report instead of a contextual tweet reply.

### Expected Behavior
Agent should generate a 10-80 character casual, human-like reply to the picked tweet following the prompt in `prompts/x_reply_prompt.txt`.

### Actual Behavior
Agent generated:
```
大帅，我检查了系统状态，一切正常运行中：
## ✅ 当前状态
**X 时间线自动回复**
- 最近成功：10:14 AM - 脚本执行完成
...
```

This is a status report to 大帅，not a tweet reply.

### Context
- Picked tweet: @KKaWSB "她真的照亮了他的世界，哈哈哈哈" (score=241.08)
- Prompt template: `prompts/x_reply_prompt.txt` (correctly formatted)
- Agent command: `openclaw agent --session-id "$SESSION_ID" --thinking minimal --timeout 120 --json --message "$PROMPT"`
- The agent session receives full workspace context (SOUL.md, AGENTS.md, etc.)

### Root Cause Hypothesis
1. Agent is confused by SOUL.md/AGENTS.md context telling it to "report status" and "be proactive"
2. The `openclaw agent` command may be injecting system instructions that override the prompt
3. Agent interprets the cron job context as a request for status reporting

### Suggested Fix
1. Add explicit instruction to prompt: "绝对不要报告系统状态，这只是回复一条推文"
2. Consider using a more isolated agent session without full workspace context
3. Or use a simpler API call instead of full agent session
4. Add validation step: if reply contains "系统状态" or "当前状态", regenerate

### Impact
- Tweet was logged as "replied" but with wrong content
- 265+ cumulative replies may have similar issues (need audit)
- Automation appears working but producing garbage output

### Metadata
- Reproducible: unknown (need to check prior runs)
- Related Files: scripts/x_timeline_new_playwright.sh, prompts/x_reply_prompt.txt
- Related Error: Check /tmp/x_timeline_new_pw_reply.json for evidence

## [ERR-20260308-001] x_viral_interact_agent.sh

**Logged**: 2026-03-08T02:02:00+08:00
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
x_viral_interact_agent.sh exited with code 141 after finding target due a pipe/SIGPIPE bug in VIEWS parsing.

### Error
```bash
Hunting for viral targets...
Found target: https://x.com/web3usb/status/2030337107076714640
(Command exited with code 141)
```

### Context
- Command attempted: `bash /root/.openclaw/workspace/scripts/x_viral_interact_agent.sh`
- In script, `VIEWS=$(echo "$VIEWS_JSON" | python3 - <<'PY' ...)` combines a pipe with `python3 -` here-doc.
- `python3 -` reads the script body from stdin and exits before consuming piped JSON, causing `echo` to hit SIGPIPE under `set -o pipefail`.

### Suggested Fix
Avoid piping into `python3 -` with heredoc. Pass JSON via env var or temp file, e.g. `python3 -c '...'` with `VIEWS_JSON` env.

### Metadata
- Reproducible: yes
- Related Files: scripts/x_viral_interact_agent.sh

---
