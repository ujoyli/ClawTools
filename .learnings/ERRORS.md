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
