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

ARTICLE_LIST_URL = "https://x.com/compose/articles"

# Exact selectors confirmed via browser inspection
COVER_FILE_INPUT = 'input[data-testid="fileInput"]'
TITLE_SELECTORS = [
    'textarea[placeholder="添加标题"]',
    'textarea[placeholder*="title" i]',
    'textarea[placeholder*="Title" i]',
]
BODY_SELECTORS = [
    'div[role="textbox"]',
    'div[contenteditable="true"]',
]
NEW_ARTICLE_SELECTORS = [
    'a[href*="/compose/articles/new"]',
    'button:has-text("撰写")',
    'button:has-text("Write")',
    'a:has-text("撰写")',
]

# Publish button
PUBLISH_BTN_SELECTORS = [
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
    """Load and normalize cookies from JSON file (EditThisCookie format)."""
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    return [_normalize_cookie(c) for c in raw if c.get("name") and c.get("domain")]


def _normalize_cookie(c: dict) -> dict:
    """
    Normalize a raw EditThisCookie entry to Playwright's expected format.

    Playwright requires sameSite to be exactly 'Strict', 'Lax', or 'None'.
    """
    ss = str(c.get("sameSite", "")).lower()
    if ss in ("none", "no_restriction"):
        same_site = "None"
    elif ss == "strict":
        same_site = "Strict"
    else:
        same_site = "Lax"

    normalized = {
        "name": c["name"],
        "value": c["value"],
        "domain": c["domain"],
        "path": c.get("path", "/"),
        "httpOnly": bool(c.get("httpOnly", False)),
        "secure": bool(c.get("secure", True)),
        "sameSite": same_site,
    }
    if c.get("expirationDate"):
        normalized["expires"] = int(c["expirationDate"])
    return normalized


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
    """
    Navigate to the article editor, fill content, and publish.

    Flow:
    1. Go to article list page
    2. Click 'New article' / '撰写' to open editor
    3. Upload cover image
    4. Fill title and body
    5. Click publish (unless dry-run)
    """
    logger.info("Navigating to article list...")
    page.goto(ARTICLE_LIST_URL, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(3000)

    _click_new_article(page)
    page.wait_for_timeout(5000)  # wait for editor to fully render

    _upload_cover_image(page, cover_image_path)
    _fill_title(page, title)
    _fill_body_with_blocks(page, blocks, insert_images)
    page.wait_for_timeout(2000)  # let autosave kick in

    if dry_run:
        page.screenshot(path="/tmp/article_preview.png")
        logger.info("Dry run — preview saved to /tmp/article_preview.png")
        logger.info("Current URL: %s", page.url)
        return

    _click_publish(page)
    logger.info("Article published! URL: %s", page.url)


def _click_new_article(page: Page) -> None:
    """Click the button/link to create a new article draft."""
    logger.info("Clicking 'New article'...")
    for sel in NEW_ARTICLE_SELECTORS:
        try:
            el = page.locator(sel).first
            if el.count() > 0 and el.is_visible(timeout=2000):
                el.click()
                logger.info("Clicked: %s", sel)
                return
        except Exception:
            continue
    # Fallback: navigate directly to new article URL
    logger.warning("'New article' button not found, navigating directly")
    page.goto("https://x.com/compose/articles/new", wait_until="domcontentloaded", timeout=60000)


def _upload_cover_image(page: Page, cover_path: str) -> None:
    """
    Upload cover image via the hidden file input (data-testid='fileInput').
    Skips gracefully if not found.
    """
    logger.info("Uploading cover image...")
    try:
        page.wait_for_selector(COVER_FILE_INPUT, timeout=10000)
        page.locator(COVER_FILE_INPUT).first.set_input_files(cover_path)
        page.wait_for_timeout(3000)
        logger.info("Cover image uploaded")
    except Exception as e:
        logger.warning("Cover image upload skipped: %s", e)


def _fill_title(page: Page, title: str) -> None:
    """Fill the article title via the textarea, trying selectors in order."""
    logger.info("Filling title: %s", title)
    for sel in TITLE_SELECTORS:
        try:
            page.wait_for_selector(sel, timeout=5000)
            el = page.locator(sel).first
            el.click()
            page.wait_for_timeout(200)
            el.fill(title)
            page.wait_for_timeout(500)
            logger.info("Title filled via: %s", sel)
            return
        except Exception:
            continue
    logger.warning("Title fill failed: no matching selector found")


def _fill_body_with_blocks(
    page: Page,
    blocks: list[ContentBlock],
    insert_images: bool,
) -> None:
    """
    Fill article body block by block.

    Text blocks: type into the Draft.js contenteditable editor.
    Image blocks: use the Insert toolbar (if insert_images is True).
    """
    logger.info("Focusing body editor...")
    focused = False
    for sel in BODY_SELECTORS:
        try:
            page.wait_for_selector(sel, timeout=5000)
            page.locator(sel).first.click()
            logger.info("Body focused via: %s", sel)
            focused = True
            break
        except Exception:
            continue
    if not focused:
        logger.warning("Body editor focus failed, clicking center")
        page.mouse.click(640, 550)
    page.wait_for_timeout(300)

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
