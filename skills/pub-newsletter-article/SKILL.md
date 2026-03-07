---
name: pub-newsletter-article
description: 从 articles/ 目录挑选一篇未发布的文章，由 agent 自己精简翻译成中文（≤2000字），发布为 Twitter/X 文章，再发一条带文章链接的推广推文，记录发布记录避免重复。Use when asked to publish, post or share a newsletter article to Twitter/X.
---

# pub-newsletter-article

将 Tech World with Milan Newsletter 文章发布到 Twitter/X 的完整流程。

**重要：LLM 摘要由你（运行此 skill 的 agent）自己完成，不需要调外部 LLM API。**

---

## 完整操作步骤

### Step 1：选取未发布文章

```bash
cd /path/to/ClawTools
python3 skills/pub-newsletter-article/scripts/pick_article.py articles/ skills/pub-newsletter-article/state/posted.json
```

输出 JSON，包含：
- `slug`：文章标识
- `title`：文章标题
- `article_md`：markdown 文件路径
- `images_dir`：图片目录路径

若输出为 `{}`，说明所有文章已发布。

---

### Step 2：阅读文章并生成中文摘要

1. 用 `view_file` 或 `read_file` 读取 `article_md` 的内容
2. **由你自己生成中文摘要**，要求：
   - ≤ 2000 字
   - 保留核心观点、关键数据、实用建议
   - 流畅自然的中文
   - 不含图片 URL 或 markdown 语法
   - 直接从正文开始，不重复标题

---

### Step 3：发布 Twitter 文章 + 推广推文

```bash
python3 skills/pub-newsletter-article/scripts/publish.py \
    --cookies /path/to/cookies.json \
    --title "文章标题" \
    --body "你生成的中文摘要正文..."
```

输出 JSON：
```json
{"article_url": "https://x.com/...", "tweet_url": "https://x.com/...", "ok": true}
```

**测试模式（不实际发布）：**
```bash
python3 ... --dry-run
```

---

### Step 4：记录已发布文章

```bash
python3 skills/pub-newsletter-article/scripts/pick_article.py mark \
    skills/pub-newsletter-article/state/posted.json \
    "<slug>" "<title>" "<article_url>"
```

---

## 所需环境变量

| 变量 | 用途 |
|------|------|
| `X_COOKIES_FILE` | Twitter cookies JSON 路径（Playwright 登录用）|
| `TWITTER_CONSUMER_KEY` | OAuth 1.0a（推广推文用）|
| `TWITTER_CONSUMER_SECRET` | 同上 |
| `TWITTER_ACCESS_TOKEN` | 同上 |
| `TWITTER_ACCESS_TOKEN_SECRET` | 同上 |

Cookies 导出：登录 Twitter → 用 [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie) 导出 JSON。

---

## 文件结构

```
skills/pub-newsletter-article/
├── SKILL.md                  # 本文档（操作手册）
├── _meta.json
├── scripts/
│   ├── pick_article.py       # 选取未发布文章 + 记录
│   └── publish.py            # 发布文章 + 推广推文
└── state/
    └── posted.json           # 已发布记录（自动维护）
```

## posted.json 格式

```json
[
  {
    "slug": "why-csharp",
    "title": "Why C#?",
    "tweet_url": "https://x.com/i/status/...",
    "posted_at": "2026-03-07T10:00:00+00:00"
  }
]
```
