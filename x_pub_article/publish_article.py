"""
Twitter/X article publisher using Playwright.

Design:
- Load cookies from a JSON file (exported via EditThisCookie or similar)
- Parse article into ordered content blocks (text + images)
- Launch browser, navigate to x.com/compose/articles
- Upload cover image via hidden file input
- Fill article: type text blocks, insert image blocks inline via toolbar
- Click publish and confirm

Usage:
    python publish_article.py --cookies cookies.json --article article.md
    python publish_article.py --cookies cookies.json --title "Why C#?" --body body.txt
"""

import argparse
import json
import logging
import time
from pathlib import Path

from playwright.sync_api import sync_playwright, Page, BrowserContext

from cover_image import generate_cover_image
from article_loader import load_article_blocks, load_article_content, ContentBlock

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

ARTICLE_URL = "https://x.com/compose/articles"

# Toolbar "Insert" button selectors
INSERT_BTN_SELECTORS = [
    'button[aria-label*="插入"]',
    'button[aria-label*="Insert" i]',
    'span:has-text("插入")',
    'span:has-text("Insert")',
]

# Insert menu → Image/Media option
INSERT_IMAGE_SELECTORS = [
    'div[role="menuitem"]:has-text("图片")',
    'div[role="menuitem"]:has-text("Image")',
    'div[role="menuitem"]:has-text("媒体")',
    'div[role="menuitem"]:has-text("Media")',
    'a:has-text("图片")',
    'a:has-text("Image")',
]

PUBLISH_BTN_SELECTORS = [
    'button[data-testid="article-publish-button"]',
    'button:has-text("发布")',
    'button:has-text("Publish")',
]

CONFIRM_BTN_SELECTORS = [
    'button[data-testid="confirmationSheetConfirm"]',
    'div[role="dialog"] button:has-text("发布")',
    'div[role="dialog"] button:has-text("Publish")',
    'div[role="dialog"] button:has-text("确认")',
]


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Publish article to Twitter/X")
    parser.add_argument("--cookies", required=True, help="Path to cookies JSON file")

    content_group = parser.add_mutually_exclusive_group(required=True)
    content_group.add_argument("--article", help="Path to markdown article file")
    content_group.add_argument("--title", help="Article title (use with --body)")

    parser.add_argument("--body", help="Body text file (used with --title)")
    parser.add_argument("--cover", help="Cover image path (auto-generated if omitted)")
    parser.add_argument("--headless", action="store_true", help="Run headlessly")
    parser.add_argument("--dry-run", action="store_true", help="Skip final publish click")
    parser.add_argument(
        "--no-images", action="store_true",
        help="Skip inline image insertion (text only)",
    )
    return parser.parse_args()


def load_cookies(path: str) -> list[dict]:
    """Load cookies from JSON file (EditThisCookie format)."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def create_context(playwright, cookies: list[dict], headless: bool) -> BrowserContext:
    """Create Playwright browser context with cookies pre-loaded."""
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
    blocks: list[ContentBlock],
    cover_image_path: str,
    dry_run: bool,
    insert_images: bool,
) -> None:
    """Navigate to article editor and publish an article with inline images."""
    logger.info("Navigating to article editor...")
    page.goto(ARTICLE_URL, wait_until="networkidle", timeout=30000)
    page.wait_for_timeout(2000)

    _upload_cover_image(page, cover_image_path)
    _fill_title(page, title)
    _fill_body_with_blocks(page, blocks, insert_images)

    if dry_run:
        page.screenshot(path="/tmp/article_preview.png")
        logger.info("Dry run — preview saved to /tmp/article_preview.png")
        return

    _click_publish(page)
    logger.info("Article published!")


def _upload_cover_image(page: Page, cover_path: str) -> None:
    """Upload cover image via the hidden file input at the top of the editor."""
    logger.info("Uploading cover image...")
    file_input = page.locator('input[type="file"]').first
    file_input.set_input_files(cover_path)
    page.wait_for_timeout(3000)


def _fill_title(page: Page, title: str) -> None:
    """Fill the article title field."""
    logger.info("Filling title: %s", title)
    selectors = [
        '[data-testid="article-title"]',
        'div[contenteditable="true"][data-placeholder*="标题"]',
        'div[contenteditable="true"][data-placeholder*="title" i]',
        'h1[contenteditable="true"]',
    ]
    _click_and_type(page, selectors, title)


def _fill_body_with_blocks(
    page: Page,
    blocks: list[ContentBlock],
    insert_images: bool,
) -> None:
    """
    Fill article body block by block.

    For text blocks: keyboard-type into the contenteditable editor.
    For image blocks: use the Insert toolbar button to upload local images.
    """
    body_selectors = [
        '[data-testid="article-body"]',
        'div[contenteditable="true"][data-placeholder*="撰写"]',
        'div[contenteditable="true"][data-placeholder*="write" i]',
        'div.public-DraftEditor-content',
    ]

    # Focus the body editor
    _focus_editor(page, body_selectors)

    image_count = 0
    for i, block in enumerate(blocks):
        if block.type == "text":
            _type_text_block(page, block.content)
        elif block.type == "image" and insert_images:
            success = _insert_image_block(page, block.content)
            if success:
                image_count += 1
            else:
                logger.warning("Failed to insert image: %s", block.content)
        # Small pause between blocks for editor stability
        page.wait_for_timeout(200)

    logger.info("Body filled: %d blocks, %d images inserted", len(blocks), image_count)


def _focus_editor(page: Page, selectors: list[str]) -> None:
    """Click into the body editor to give it focus."""
    for sel in selectors:
        try:
            el = page.locator(sel).first
            if el.count() > 0:
                el.click()
                page.wait_for_timeout(300)
                return
        except Exception:
            continue
    page.mouse.click(640, 550)
    page.wait_for_timeout(300)


def _type_text_block(page: Page, text: str) -> None:
    """Type a text block into the focused editor."""
    if not text.strip():
        return
    page.keyboard.type(text, delay=5)
    page.keyboard.press("Enter")
    page.keyboard.press("Enter")


def _insert_image_block(page: Page, image_path: str) -> bool:
    """
    Insert an image at the current cursor position via the Insert toolbar.

    Flow: click Insert button → click Image option → set file on hidden input.
    Returns True on success.
    """
    logger.debug("Inserting image: %s", image_path)

    # Click the Insert button in toolbar
    if not _click_first_matching(page, INSERT_BTN_SELECTORS):
        logger.warning("Insert button not found")
        return False
    page.wait_for_timeout(600)

    # Click the image/media option in the dropdown
    if not _click_first_matching(page, INSERT_IMAGE_SELECTORS):
        logger.warning("Insert image menu item not found")
        # Close the open menu
        page.keyboard.press("Escape")
        return False
    page.wait_for_timeout(800)

    # Set the file on the newly appeared file input
    try:
        file_inputs = page.locator('input[type="file"]')
        # Use the last file input (the one just triggered by Insert menu)
        count = file_inputs.count()
        if count == 0:
            return False
        file_inputs.nth(count - 1).set_input_files(image_path)
        page.wait_for_timeout(2000)
        return True
    except Exception as e:
        logger.warning("File input error: %s", e)
        return False


def _click_first_matching(page: Page, selectors: list[str]) -> bool:
    """Try each selector and click the first one found. Returns True on success."""
    for sel in selectors:
        try:
            el = page.locator(sel).first
            if el.count() > 0 and el.is_visible():
                el.click()
                return True
        except Exception:
            continue
    return False


def _click_and_type(page: Page, selectors: list[str], text: str) -> None:
    """Click the first matching element and type text into it."""
    for sel in selectors:
        try:
            el = page.locator(sel).first
            if el.count() > 0:
                el.click()
                page.wait_for_timeout(300)
                page.keyboard.press("Meta+a")
                page.keyboard.type(text, delay=10)
                return
        except Exception:
            continue
    page.mouse.click(640, 400)
    page.keyboard.type(text, delay=10)


def _click_publish(page: Page) -> None:
    """Click publish button then confirm in dialog."""
    _click_first_matching(page, PUBLISH_BTN_SELECTORS)
    page.wait_for_timeout(2000)
    _click_first_matching(page, CONFIRM_BTN_SELECTORS)
    page.wait_for_timeout(3000)


def main() -> None:
    """Entry point."""
    args = parse_args()

    # Load article content
    if args.article:
        title, blocks = load_article_blocks(args.article)
    else:
        title = args.title
        body_text = Path(args.body).read_text(encoding="utf-8") if args.body else title
        from article_loader import ContentBlock as CB
        blocks = [CB(type="text", content=body_text)]

    text_blocks = sum(1 for b in blocks if b.type == "text")
    img_blocks = sum(1 for b in blocks if b.type == "image")
    logger.info("Article: %s | %d text blocks, %d image blocks", title, text_blocks, img_blocks)

    # Resolve or generate cover image
    if args.cover:
        cover_path = args.cover
    else:
        cover_path = f"/tmp/cover_{int(time.time())}.png"
        generate_cover_image(title, cover_path)
        logger.info("Generated cover: %s", cover_path)

    cookies = load_cookies(args.cookies)
    logger.info("Loaded %d cookies", len(cookies))

    insert_images = not args.no_images
    with sync_playwright() as pw:
        context = create_context(pw, cookies, args.headless)
        page = context.new_page()
        try:
            publish_article(page, title, blocks, cover_path, args.dry_run, insert_images)
        finally:
            context.close()


if __name__ == "__main__":
    main()
