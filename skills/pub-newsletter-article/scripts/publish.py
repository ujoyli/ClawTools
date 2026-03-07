"""
Publish a Twitter/X Article and post a promotional tweet.

This script handles ONLY the mechanical publishing work.
The agent is responsible for:
  1. Calling pick_article.py to select an article
  2. Reading the article content
  3. Generating a Chinese summary (≤2000 chars)
  4. Calling this script with the summarized content
  5. Calling mark_posted.py to record after success

Usage:
    python3 scripts/publish.py \
        --cookies /path/to/cookies.json \
        --title "文章标题" \
        --body "精简后的中文正文..." \
        --article-url "https://x.com/..."   # set after article is published
        [--dry-run]

Environment (for promo tweet):
    TWITTER_CONSUMER_KEY
    TWITTER_CONSUMER_SECRET
    TWITTER_ACCESS_TOKEN
    TWITTER_ACCESS_TOKEN_SECRET
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SKILL_DIR = SCRIPT_DIR.parent
REPO_ROOT = SKILL_DIR.parent.parent

X_PUB_ARTICLE_DIR = REPO_ROOT / "x_pub_article"
PUBLISH_SCRIPT = X_PUB_ARTICLE_DIR / "publish_article.py"
TWEET_JS = REPO_ROOT / "skills" / "twitter-post" / "scripts" / "tweet.js"

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

PROMO_TEMPLATE = "📖 刚发布了一篇新文章：《{title}》\n\n{teaser}\n\n🔗 {url}"
TEASER_MAX_CHARS = 80


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--cookies", required=True, help="Twitter cookies JSON path")
    p.add_argument("--title", required=True, help="Article title")
    p.add_argument("--body", required=True, help="Summarized article body (Chinese text)")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def write_temp_article(title: str, body: str) -> str:
    """Write title + body to a temp markdown file for publish_article.py."""
    tmp = f"/tmp/article_{int(time.time())}.md"
    Path(tmp).write_text(f"# {title}\n\n{body}", encoding="utf-8")
    return tmp


def publish_article(cookies: str, title: str, body: str, dry_run: bool) -> str:
    """
    Publish the article via Playwright, return the article URL.

    Calls x_pub_article/publish_article.py as a subprocess.
    On dry-run, returns a placeholder URL.
    """
    if dry_run:
        logger.info("[DRY RUN] Would publish: %s", title)
        return "https://x.com/dry-run/article"

    if not Path(cookies).exists():
        raise FileNotFoundError(f"Cookies file not found: {cookies}")

    tmp_md = write_temp_article(title, body)
    cmd = ["python3", str(PUBLISH_SCRIPT), "--cookies", cookies, "--article", tmp_md]
    logger.info("Publishing article via Playwright...")
    result = subprocess.run(cmd, capture_output=True, text=True,
                            cwd=str(X_PUB_ARTICLE_DIR), timeout=180)

    logger.info("publish stdout: %s", result.stdout)
    if result.returncode != 0:
        logger.error("publish stderr: %s", result.stderr)

    # Try to extract article URL from stdout
    for line in result.stdout.splitlines():
        line = line.strip()
        if "x.com" in line and ("article" in line or "status" in line):
            return line
    return "https://x.com"


def post_promo_tweet(title: str, body: str, article_url: str, dry_run: bool) -> dict:
    """Post a promotional tweet with the article URL."""
    teaser = body[:TEASER_MAX_CHARS].rstrip()
    if len(body) > TEASER_MAX_CHARS:
        cut = teaser.rfind("，")
        teaser = teaser[:cut + 1] if cut > 40 else teaser + "…"

    tweet_text = PROMO_TEMPLATE.format(title=title, teaser=teaser, url=article_url)

    if dry_run:
        logger.info("[DRY RUN] Promo tweet:\n%s", tweet_text)
        return {"ok": True, "url": "https://x.com/dry-run/tweet"}

    result = subprocess.run(
        ["node", str(TWEET_JS), tweet_text],
        capture_output=True, text=True, env=os.environ.copy(), timeout=60,
    )
    output = result.stdout.strip()
    if not output:
        raise RuntimeError(f"tweet.js no output. stderr: {result.stderr}")
    return json.loads(output)


def main() -> None:
    args = parse_args()

    # 1. Publish Twitter Article
    article_url = publish_article(args.cookies, args.title, args.body, args.dry_run)
    logger.info("Article URL: %s", article_url)

    # 2. Promo tweet
    promo = post_promo_tweet(args.title, args.body, article_url, args.dry_run)
    if promo.get("ok"):
        logger.info("Promo tweet: %s", promo.get("url"))
    else:
        logger.error("Promo tweet failed: %s", promo.get("error"))

    # Output result as JSON for the agent to parse
    print(json.dumps({
        "article_url": article_url,
        "tweet_url": promo.get("url"),
        "ok": promo.get("ok", False),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
