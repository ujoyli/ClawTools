# LEARNINGS

## [LRN-20260226-001] best_practice

**Logged**: 2026-02-26T15:40:00+08:00
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
Discord Webhook has a ~2000 character limit for `content`; TrendRadar default batch size (4000 bytes) can cause 400 errors unless message splitting is configured appropriately.

### Details
- Using TrendRadar generic webhook to Discord failed with HTTP 400:
  `{"content": ["Must be 2000 or fewer in length."]}`
- TrendRadar supports message batching/splitting via `advanced.batch_size.default` (bytes) and will send multiple batches.

### Suggested Action
- When targeting Discord via generic webhook, set `advanced.batch_size.default` to a conservative value (e.g., 1800 bytes) and keep `GENERIC_WEBHOOK_TEMPLATE` simple (e.g., `{ "content": "{content}" }`) so splitting works.
- Consider also limiting `report.max_news_per_keyword` to reduce spam.

### Metadata
- Source: conversation
- Related Files: TrendRadar/config/config.yaml, TrendRadar/docker/.env
- Tags: discord, webhook, message-splitting, docker
- Pattern-Key: harden.discord_webhook_message_size
- Recurrence-Count: 1
- First-Seen: 2026-02-26
- Last-Seen: 2026-02-26

---
