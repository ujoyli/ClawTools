---
name: browserwing
description: Unified BrowserWing skill (admin + executor). Manage BrowserWing service, LLM configs, scripts, and control browser automation via executor APIs.
read_when:
  - Need BrowserWing API automation
  - Need stable browser control through /api/v1/executor endpoints
allowed-tools: Bash(curl:*)
defaults:
  host: http://127.0.0.1
  port: 18080
---

# BrowserWing — Admin + Executor Skill

This integrated skill combines BrowserWing Admin and Executor functionality into one SKILL.md for import into our AI tooling.

Service base URL (default): ${host}:${port}  # adjust to 8080 if your deployment uses that port

## Overview

BrowserWing is a browser automation platform with AI integration. This skill exposes both admin-level controls (install, LLM config, AI exploration, scripts, MCP integration) and low-level executor controls (navigate, click, type, extract, snapshot, screenshot, batch ops).

---

## Admin Features (from SKILL_ADMIN.md)

- Install and verify Chrome
- Configure and manage LLMs (OpenAI, Anthropic, DeepSeek)
- Start/stop AI exploration to auto-generate scripts
- Manage scripts: list, create, update, delete, export as SKILL.md
- Execute scripts and retrieve execution results
- MCP integration and MCP command listing
- Cookie and browser instance management
- Troubleshooting and health checks

### Useful Admin endpoints
- GET /health
- GET /api/v1/llm-configs
- POST /api/v1/llm-configs
- POST /api/v1/ai-explore/start
- POST /api/v1/scripts/export/skill
- GET /api/v1/mcp/status

(See full Admin docs in source SKILL_ADMIN.md — includes install commands, examples, and troubleshooting tips.)

---

## Executor Features (from SKILL_EXECUTOR.md)

Core executor API base: /api/v1/executor

Capabilities:
- Navigate: POST /executor/navigate
- Snapshot (accessibility tree): GET /executor/snapshot — use after navigation to obtain RefIDs
- Click: POST /executor/click (identifier: RefID, CSS, XPath, text)
- Type: POST /executor/type
- Extract: POST /executor/extract
- Wait: POST /executor/wait
- Batch: POST /executor/batch
- Tabs management: POST /executor/tabs or via MCP tools/call
- Screenshots: POST /executor/screenshot
- Evaluate JS: POST /executor/evaluate

Executor guidelines:
- Always call /snapshot after navigation to get RefIDs (@e1, @e2)
- Prefer RefIDs for reliability
- Use /wait for dynamic content
- Use /batch for multi-step flows

Example flow (search & extract):
1) POST ${host}:${port}/api/v1/executor/navigate {"url":"https://example.com/search"}
2) GET ${host}:${port}/api/v1/executor/snapshot
3) POST ${host}:${port}/api/v1/executor/type {"identifier":"@e3", "text":"laptop"}
4) POST ${host}:${port}/api/v1/executor/press-key {"key":"Enter"}
5) POST ${host}:${port}/api/v1/executor/wait {"identifier":".search-results","state":"visible","timeout":10}
6) POST ${host}:${port}/api/v1/executor/extract {"selector":".result-item","fields":["text","href"],"multiple":true}

---

## Authentication
Use X-BrowserWing-Key header or Authorization: Bearer <token> when BrowserWing is configured with API keys/JWT.

Security note:
- Never commit real API keys or tokens to version control. Store secrets in .credentials/ or your environment secret manager.
- SKILL.md may contain example curl commands that reference localhost; adapt host/port and auth headers for your deployment.

---

## Notes for our workspace
- Default local port in our environment historically used by skills: 18080 (TOOLS.md mentions BrowserWing server at http://localhost:18080). Official SKILLs use 8080. Adjust ${port} accordingly.
- This SKILL.md merges admin and executor docs; if importing into a skills registry that expects separate admin/executor skills, split manually.

---

## Troubleshooting & Best Practices
- Call GET ${host}:${port}/health first to ensure service is running
- Keep Chrome/Chromium process count low; kill stale processes if necessary
- If LLM features fail, verify LLM configs via POST ${host}:${port}/api/v1/llm-configs/test
- For automation reliability, prefer RefIDs from /snapshot and re-snapshot after navigation or major DOM changes

---

# Raw Source References
- Original Admin skill: https://raw.githubusercontent.com/browserwing/browserwing/main/SKILL_ADMIN.md
- Original Executor skill: https://raw.githubusercontent.com/browserwing/browserwing/main/SKILL_EXECUTOR.md

---

# Example: quick health check
curl -s ${host}:${port}/health
