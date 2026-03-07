---
name: pub-newsletter-article
description: 从 articles/ 目录选一篇未发布的文章，用 LLM 精简翻译成中文（≤2000字），发布为 Twitter/X 文章（Playwright），然后发一条带文章链接的推广推文。Use this skill when asked to publish, post, or share an article from the newsletter collection.
---

# pub-newsletter-article

自动化发布 Tech World with Milan Newsletter 文章到 Twitter/X 的完整流程。

## 流程

```
articles/ 未发布文章
    ↓ pick_article.py（随机选一篇）
    ↓ LLM 精简 + 翻译（中文 ≤2000字）
    ↓ x_pub_article/publish_article.py（Playwright 发布文章）
    ↓ tweet.js（发推广推文，带文章链接）
    ↓ state/posted.json（记录，避免重复）
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `X_COOKIES_FILE` | Twitter cookies JSON 路径（用于 Playwright 登录）|
| `OPENAI_API_KEY` | 或 `ANTHROPIC_API_KEY` / `GEMINI_API_KEY`（LLM 摘要）|
| `TWITTER_CONSUMER_KEY` | Twitter API OAuth 1.0a（用于发推广推文）|
| `TWITTER_CONSUMER_SECRET` | 同上 |
| `TWITTER_ACCESS_TOKEN` | 同上 |
| `TWITTER_ACCESS_TOKEN_SECRET` | 同上 |

## 使用

```bash
cd /path/to/ClawTools

# 运行完整发布流程
python3 skills/pub-newsletter-article/scripts/run.py \
    --cookies /path/to/cookies.json

# 指定特定文章
python3 skills/pub-newsletter-article/scripts/run.py \
    --cookies /path/to/cookies.json \
    --slug why-csharp

# 测试模式（不实际发布）
python3 skills/pub-newsletter-article/scripts/run.py \
    --cookies /path/to/cookies.json \
    --dry-run
```

## 文件结构

```
skills/pub-newsletter-article/
├── SKILL.md             # 本文档
├── _meta.json           # skill 元数据
├── scripts/
│   ├── run.py           # 主流程（入口）
│   └── pick_article.py  # 文章选取 + 记录
└── state/
    └── posted.json      # 已发布记录（自动维护）
```

## 依赖

- `x_pub_article/` 目录（Playwright 发文章脚本）
- `skills/twitter-post/scripts/tweet.js`（发推广推文）
- `articles/` 目录（爬取的 newsletter 文章）

### 安装依赖

```bash
# Playwright
cd x_pub_article && pip install -r requirements.txt
python -m playwright install chromium

# twitter-post
cd skills/twitter-post && npm install
```

## Cookies 导出

1. 登录 Twitter/X
2. 使用 [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie) 导出
3. 保存为 JSON 文件，路径设置到 `X_COOKIES_FILE`

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

## 注意

- Twitter 文章编辑器的 CSS 选择器可能随版本更新失效，如遇图片未插入请检查 `x_pub_article/publish_article.py`
- 推广推文使用 OAuth 1.0a API，需要开发者账号权限 Read+Write
