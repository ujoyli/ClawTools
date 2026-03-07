"""
Main runner for pub-newsletter-article skill.

Pipeline:
1. pick_article      — select a random unposted article from articles/
2. summarize         — LLM condense + translate to Chinese (≤2000 chars)
3. publish_article   — publish as a Twitter/X Article via Playwright (x_pub_article)
4. promote_tweet     — post a promotional tweet with the article URL
5. mark_posted       — record slug + article URL in state/posted.json

Environment:
    OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY — for summarization
    TWITTER_CONSUMER_KEY, TWITTER_CONSUMER_SECRET,
    TWITTER_ACCESS_TOKEN, TWITTER_ACCESS_TOKEN_SECRET   — for promo tweet
    X_COOKIES_FILE — path to Twitter cookies JSON (for Playwright article publish)

Usage:
    python scripts/run.py [--dry-run] [--slug <slug>] [--cookies <path>]
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

SKILL_DIR = Path(__file__).parent.parent
REPO_ROOT = SKILL_DIR.parent.parent
ARTICLES_DIR = REPO_ROOT / "articles"
STATE_FILE = SKILL_DIR / "state" / "posted.json"

X_PUB_ARTICLE_DIR = REPO_ROOT / "x_pub_article"
PUBLISH_SCRIPT = X_PUB_ARTICLE_DIR / "publish_article.py"
COVER_IMAGE_PY = X_PUB_ARTICLE_DIR / "cover_image.py"
TWEET_JS = REPO_ROOT / "skills" / "twitter-post" / "scripts" / "tweet.js"

sys.path.insert(0, str(SKILL_DIR / "scripts"))
from pick_article import pick_article, mark_posted

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

SUMMARY_MAX_CHARS = 2000
# Promotional tweet template — article URL is appended automatically
PROMO_TEMPLATE = "📖 刚发布了一篇新文章：《{title}》\n\n{teaser}\n\n🔗 {url}"
TEASER_MAX_CHARS = 100


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true", help="Skip actual publishing and posting")
    p.add_argument("--slug", help="Force a specific article slug")
    p.add_argument("--cookies", default=os.getenv("X_COOKIES_FILE"), help="Twitter cookies JSON path")
    return p.parse_args()


def pick(slug_override: Optional[str]) -> dict:
    """Pick an unposted article, or force a specific slug."""
    if slug_override:
        md = ARTICLES_DIR / slug_override / "article.md"
        if not md.exists():
            raise FileNotFoundError(f"Article not found: {md}")
        return {
            "slug": slug_override,
            "title": _extract_title(md),
            "article_md": str(md),
            "images_dir": str(ARTICLES_DIR / slug_override / "images"),
        }
    article = pick_article(ARTICLES_DIR, STATE_FILE)
    if not article:
        raise RuntimeError("All articles have been posted!")
    return article


def _extract_title(md_file: Path) -> str:
    """Extract title from markdown front matter or first H1."""
    for line in md_file.read_text(encoding="utf-8").splitlines()[:20]:
        if line.startswith("title:"):
            return line[6:].strip().strip('"').strip("'")
    for line in md_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return md_file.parent.name


def summarize_and_translate(article_md: str) -> str:
    """
    Use LLM to summarize the article to ≤2000 Chinese characters.
    Falls back to empty string if no API key is configured.
    """
    text = Path(article_md).read_text(encoding="utf-8")
    prompt = _build_summary_prompt(text)
    result = _call_llm(prompt)
    return result[:SUMMARY_MAX_CHARS] if len(result) > SUMMARY_MAX_CHARS else result


def _build_summary_prompt(article_text: str) -> str:
    """Build the summarization prompt for LLM."""
    truncated = article_text[:8000]
    return f"""请将以下英文文章精华提炼并翻译成中文。

要求：
- 输出纯文本，不超过 2000 字
- 保留核心观点、关键数据和实用建议
- 使用流畅自然的中文
- 不要输出标题，直接从正文开始
- 不要包含图片 URL 或 markdown 语法

---
{truncated}
---

请直接输出中文摘要："""


def _call_llm(prompt: str) -> str:
    """Dispatch to whichever LLM API key is available."""
    if os.getenv("OPENAI_API_KEY"):
        return _call_openai(prompt)
    if os.getenv("ANTHROPIC_API_KEY"):
        return _call_anthropic(prompt)
    if os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY"):
        return _call_gemini(prompt)
    logger.warning("No LLM API key — skipping summarization")
    return ""


def _call_openai(prompt: str) -> str:
    import urllib.request
    body = json.dumps({
        "model": "gpt-4o-mini",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 1200,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}",
                 "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)["choices"][0]["message"]["content"].strip()


def _call_anthropic(prompt: str) -> str:
    import urllib.request
    body = json.dumps({
        "model": "claude-3-haiku-20240307", "max_tokens": 1200,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"x-api-key": os.environ["ANTHROPIC_API_KEY"],
                 "anthropic-version": "2023-06-01",
                 "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)["content"][0]["text"].strip()


def pick_best_image(images_dir: str) -> Optional[str]:
    """Return path to the first image in article's images/ dir, or None."""
    images_path = Path(images_dir)
    if not images_path.exists():
        return None
    for ext in ("*.png", "*.jpg", "*.jpeg", "*.webp"):
        matches = sorted(images_path.glob(ext))
        if matches:
            return str(matches[0])
    return None


def _call_gemini(prompt: str) -> str:
    import urllib.request
    key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={key}"
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)["candidates"][0]["content"]["parts"][0]["text"].strip()


def publish_article(article: dict, summary: str, cookies: str, dry_run: bool) -> str:
    """
    Publish the article as a Twitter/X Article via Playwright.

    Writes a temporary markdown file with the Chinese summary as body,
    then calls x_pub_article/publish_article.py.
    Returns the article URL (or a placeholder on dry-run).
    """
    if dry_run:
        logger.info("[DRY RUN] Would publish article: %s", article["title"])
        return "https://x.com/dry-run/article"

    if not cookies or not Path(cookies).exists():
        raise FileNotFoundError(
            f"Cookies file not found: {cookies}. "
            "Set X_COOKIES_FILE env var or use --cookies."
        )

    # Write a temp markdown with the Chinese summary as body
    tmp_md = f"/tmp/article_{int(time.time())}.md"
    Path(tmp_md).write_text(
        f"# {article['title']}\n\n{summary}", encoding="utf-8"
    )

    cmd = [
        "python3", str(PUBLISH_SCRIPT),
        "--cookies", cookies,
        "--article", tmp_md,
    ]
    logger.info("Publishing article via Playwright...")
    result = subprocess.run(cmd, capture_output=True, text=True,
                            cwd=str(X_PUB_ARTICLE_DIR), timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f"publish_article.py failed:\n{result.stderr}")

    logger.info("Article published")
    # parse URL from stdout if available
    for line in result.stdout.splitlines():
        if "x.com" in line and "article" in line:
            return line.strip()
    return "https://x.com"


def post_promo_tweet(title: str, summary: str, article_url: str, dry_run: bool) -> dict:
    """
    Post a promotional tweet with the article link.
    Uses twitter-post skill's tweet.js (OAuth 1.0a).
    """
    teaser = summary[:TEASER_MAX_CHARS].rstrip()
    if len(summary) > TEASER_MAX_CHARS:
        teaser = teaser[:teaser.rfind("，") + 1] if "，" in teaser else teaser + "…"

    tweet_text = PROMO_TEMPLATE.format(
        title=title, teaser=teaser, url=article_url
    )

    if dry_run:
        logger.info("[DRY RUN] Promo tweet:\n%s", tweet_text)
        return {"ok": True, "url": "https://x.com/dry-run/tweet"}

    env = os.environ.copy()
    cmd = ["node", str(TWEET_JS), tweet_text]
    result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
    output = result.stdout.strip()
    if not output:
        raise RuntimeError(f"tweet.js returned no output. stderr: {result.stderr}")
    return json.loads(output)


def main() -> None:
    """Run the full publish pipeline."""
    args = parse_args()

    # 1. Pick article
    article = pick(args.slug)
    logger.info("Selected: %s — %s", article["slug"], article["title"])

    # 2. Summarize + translate
    logger.info("Summarizing article...")
    summary = summarize_and_translate(article["article_md"])
    if not summary:
        summary = "（本文精华提炼暂不可用，请阅读原文）"
    logger.info("Summary: %d chars", len(summary))

    # 3. Publish as Twitter Article
    article_url = publish_article(article, summary, args.cookies, args.dry_run)
    logger.info("Article URL: %s", article_url)

    # 4. Post promotional tweet
    promo = post_promo_tweet(article["title"], summary, article_url, args.dry_run)
    if not promo.get("ok"):
        logger.error("Promo tweet failed: %s", promo.get("error"))
    else:
        logger.info("Promo tweet: %s", promo.get("url"))

    # 5. Record
    if not args.dry_run:
        mark_posted(STATE_FILE, article["slug"], article["title"], article_url)
        logger.info("Recorded in posted.json")


if __name__ == "__main__":
    main()
