"""
Twitter/X article publisher using Playwright.

Design:
- Load cookies from a JSON file (exported via EditThisCookie or similar)
- Accept article title and body text as CLI arguments or from a file
- Generate a cover image using Pillow with the article title
- Launch browser, navigate to x.com/compose/articles
- Fill in title, body, upload cover image via the hidden file input
- Click publish and confirm

Usage:
    python publish_article.py --cookies cookies.json --title "Why C#?" --body body.txt
    python publish_article.py --cookies cookies.json --article article.md
"""

import argparse
import json
import logging
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright, Page, BrowserContext

from cover_image import generate_cover_image
from article_loader import load_article_content

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

ARTICLE_URL = "https://x.com/compose/articles"


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Publish article to Twitter/X")
    parser.add_argument("--cookies", required=True, help="Path to cookies JSON file")

    content_group = parser.add_mutually_exclusive_group(required=True)
    content_group.add_argument("--article", help="Path to markdown article file")
    content_group.add_argument("--title", help="Article title (use with --body)")

    parser.add_argument("--body", help="Path to body text file (used with --title)")
    parser.add_argument("--cover", help="Path to cover image (auto-generated if omitted)")
    parser.add_argument("--headless", action="store_true", help="Run browser headlessly")
    parser.add_argument("--dry-run", action="store_true", help="Skip final publish click")
    return parser.parse_args()


def load_cookies(cookies_path: str) -> list[dict]:
    """Load cookies from a JSON file (EditThisCookie format or Playwright format)."""
    with open(cookies_path, encoding="utf-8") as f:
        data = json.load(f)

    # EditThisCookie exports a list of dicts with 'name', 'value', 'domain', etc.
    # Playwright expects the same structure so no conversion needed usually.
    return data


def create_browser_context(playwright, cookies: list[dict], headless: bool) -> BrowserContext:
    """Create a Playwright browser context with the given cookies loaded."""
    browser = playwright.chromium.launch(headless=headless)
    context = browser.new_context(
        viewport={"width": 1280, "height": 900},
        user_agent=(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
    )
    context.add_cookies(cookies)
    return context


def publish_article(
    page: Page,
    title: str,
    body: str,
    cover_image_path: str,
    dry_run: bool,
) -> None:
    """
    Navigate to the Twitter article editor and publish an article.

    Steps:
    1. Navigate and wait for editor to load
    2. Upload cover image via hidden file input
    3. Fill title field
    4. Fill body content
    5. Click publish and confirm
    """
    logger.info("Navigating to article editor...")
    page.goto(ARTICLE_URL, wait_until="networkidle", timeout=30000)
    page.wait_for_timeout(2000)

    _upload_cover_image(page, cover_image_path)
    _fill_title(page, title)
    _fill_body(page, body)

    if dry_run:
        logger.info("Dry run — skipping publish. Screenshot saved.")
        page.screenshot(path="/tmp/article_preview.png")
        return

    _click_publish(page)
    logger.info("Article published successfully!")


def _upload_cover_image(page: Page, cover_image_path: str) -> None:
    """Upload cover image by setting the hidden file input directly."""
    logger.info("Uploading cover image: %s", cover_image_path)
    # Twitter's article editor uses a hidden file input for cover image
    file_input = page.locator('input[type="file"]').first
    file_input.set_input_files(cover_image_path)
    page.wait_for_timeout(3000)
    logger.info("Cover image uploaded")


def _fill_title(page: Page, title: str) -> None:
    """Click the title field and type the article title."""
    logger.info("Filling title: %s", title)
    title_selectors = [
        '[data-testid="article-title"]',
        'div[contenteditable="true"][data-placeholder*="标题"]',
        'div[contenteditable="true"][data-placeholder*="title" i]',
        'h1[contenteditable="true"]',
    ]
    _fill_contenteditable(page, title_selectors, title)


def _fill_body(page: Page, body: str) -> None:
    """Click the body field and type the article body."""
    logger.info("Filling body (%d chars)", len(body))
    body_selectors = [
        '[data-testid="article-body"]',
        'div[contenteditable="true"][data-placeholder*="撰写"]',
        'div[contenteditable="true"][data-placeholder*="write" i]',
        'div.public-DraftEditor-content',
    ]
    _fill_contenteditable(page, body_selectors, body)


def _fill_contenteditable(page: Page, selectors: list[str], text: str) -> None:
    """
    Try each selector until one matches, then click and type.

    Uses keyboard input for rich text editors that don't accept value assignment.
    """
    for selector in selectors:
        try:
            element = page.locator(selector).first
            if element.count() > 0:
                element.click()
                page.wait_for_timeout(500)
                # Select all and replace if any existing content
                page.keyboard.press("Meta+a")
                page.keyboard.type(text, delay=10)
                logger.debug("Filled using selector: %s", selector)
                return
        except Exception:
            continue
    # Fallback: click center of editor area and type
    logger.warning("No matching selector found, clicking center of page")
    page.mouse.click(640, 500)
    page.keyboard.type(text, delay=10)


def _click_publish(page: Page) -> None:
    """Click the publish button and confirm in any dialog."""
    logger.info("Clicking publish button...")
    publish_selectors = [
        'button[data-testid="article-publish-button"]',
        'button:has-text("发布")',
        'button:has-text("Publish")',
    ]
    for selector in publish_selectors:
        try:
            btn = page.locator(selector).first
            if btn.count() > 0:
                btn.click()
                page.wait_for_timeout(2000)
                break
        except Exception:
            continue

    # Handle confirmation dialog if it appears
    _confirm_publish_dialog(page)


def _confirm_publish_dialog(page: Page) -> None:
    """If a confirmation dialog appears, click the final confirm button."""
    confirm_selectors = [
        'button[data-testid="confirmationSheetConfirm"]',
        'div[role="dialog"] button:has-text("发布")',
        'div[role="dialog"] button:has-text("Publish")',
        'div[role="dialog"] button:has-text("确认")',
    ]
    page.wait_for_timeout(1500)
    for selector in confirm_selectors:
        try:
            btn = page.locator(selector).first
            if btn.count() > 0:
                logger.info("Confirming publish dialog...")
                btn.click()
                page.wait_for_timeout(3000)
                return
        except Exception:
            continue


def main() -> None:
    """Entry point."""
    args = parse_args()

    # Load article content
    if args.article:
        title, body = load_article_content(args.article)
    else:
        title = args.title
        body = Path(args.body).read_text(encoding="utf-8") if args.body else title

    logger.info("Article: %s (%d body chars)", title, len(body))

    # Resolve or generate cover image
    if args.cover:
        cover_path = args.cover
    else:
        cover_path = f"/tmp/cover_{int(time.time())}.png"
        generate_cover_image(title, cover_path)

    # Load cookies
    cookies = load_cookies(args.cookies)
    logger.info("Loaded %d cookies", len(cookies))

    with sync_playwright() as playwright:
        context = create_browser_context(playwright, cookies, args.headless)
        page = context.new_page()
        try:
            publish_article(page, title, body, cover_path, args.dry_run)
        finally:
            context.close()


if __name__ == "__main__":
    main()
