"""
Article content loader for Twitter publisher.

Parses articles into ordered content blocks (text and images),
preserving the original layout sequence for inline image insertion.

Two return formats:
- load_article_blocks(path) -> (title, List[ContentBlock])   # structured
- load_article_content(path) -> (title, str)                  # plain text only (legacy)
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class ContentBlock:
    """A single unit of article content: either a paragraph of text or an image."""
    type: str   # "text" or "image"
    content: str  # text string, or absolute path to image file


def load_article_blocks(filepath: str) -> tuple[str, list[ContentBlock]]:
    """
    Parse an article file into (title, [ContentBlock, ...]).

    Image blocks reference local file paths resolved relative to the article file.
    Only images that exist on disk are included as image blocks.
    """
    text = Path(filepath).read_text(encoding="utf-8")
    article_dir = Path(filepath).parent

    if filepath.endswith(".md"):
        return _parse_markdown_blocks(text, article_dir)
    return _parse_plaintext_blocks(text)


def load_article_content(filepath: str) -> tuple[str, str]:
    """
    Legacy API: return (title, plain_text_body) with images stripped.
    Used when image insertion is not needed.
    """
    title, blocks = load_article_blocks(filepath)
    text_parts = [b.content for b in blocks if b.type == "text"]
    return title, "\n\n".join(text_parts)


def _parse_markdown_blocks(text: str, article_dir: Path) -> tuple[str, list[ContentBlock]]:
    """Parse markdown into title + ordered content blocks."""
    title, body_start = _extract_frontmatter_title(text)
    remaining = text[body_start:]

    # Strip first H1 if it duplicates the front matter title
    remaining = re.sub(r"^#\s+.+\n", "", remaining, count=1)
    # Strip italic subtitle
    remaining = re.sub(r"^\*.+\*\n", "", remaining, count=1)

    blocks = _split_into_blocks(remaining, article_dir)
    return title, blocks


def _split_into_blocks(md: str, article_dir: Path) -> list[ContentBlock]:
    """
    Split markdown body into alternating text and image blocks.

    Scans for image patterns, splits surrounding text, resolves
    local image paths. Skips images that don't exist on disk.
    """
    # Unwrap linked images: [![](img_path)](link_url) → ![](img_path)
    # This pattern is common in Substack-exported markdown where images are clickable.
    md = re.sub(r"\[(!?\[[^\]]*\]\([^\)]+\))\]\([^\)]+\)", r"\1", md)

    # Match markdown image syntax: ![alt](path)
    image_pattern = re.compile(r"!\[([^\]]*)\]\(([^\)]+)\)")
    blocks: list[ContentBlock] = []
    last_end = 0

    for match in image_pattern.finditer(md):
        # Text before this image
        text_before = md[last_end:match.start()]
        cleaned = _clean_markdown_text(text_before)
        if cleaned.strip():
            blocks.append(ContentBlock(type="text", content=cleaned.strip()))

        # Image block
        img_path_str = match.group(2)
        img_path = _resolve_image_path(img_path_str, article_dir)
        if img_path:
            blocks.append(ContentBlock(type="image", content=str(img_path)))

        last_end = match.end()

    # Remaining text after last image
    remaining_text = md[last_end:]
    cleaned = _clean_markdown_text(remaining_text)
    if cleaned.strip():
        blocks.append(ContentBlock(type="text", content=cleaned.strip()))

    return blocks


def _resolve_image_path(img_ref: str, article_dir: Path) -> Optional[Path]:
    """
    Resolve an image reference to an absolute local path.

    Returns None if the path is a remote URL or the file doesn't exist.
    """
    if img_ref.startswith("http://") or img_ref.startswith("https://"):
        return None
    candidate = article_dir / img_ref
    return candidate if candidate.exists() else None


def _clean_markdown_text(md: str) -> str:
    """Convert a markdown snippet to plain text (no images, cleaned markup)."""
    # Remove any remaining image tags
    text = re.sub(r"!\[.*?\]\(.*?\)", "", md)
    # Convert links to text only
    text = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", text)
    # Remove HTML tags
    text = re.sub(r"<[^>]+>", "", text)
    # Bold/italic
    text = re.sub(r"\*{1,3}([^\*]+)\*{1,3}", r"\1", text)
    text = re.sub(r"_{1,3}([^_]+)_{1,3}", r"\1", text)
    # Headings
    text = re.sub(r"^#{1,6}\s+(.+)$", r"\n\1\n", text, flags=re.MULTILINE)
    # Horizontal rules
    text = re.sub(r"^[-*_]{3,}\s*$", "\n", text, flags=re.MULTILINE)
    # Blockquotes
    text = re.sub(r"^>\s*", "", text, flags=re.MULTILINE)
    # Inline code
    text = re.sub(r"`{1,3}([^`]+)`{1,3}", r"\1", text)
    # Collapse blanks
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def _extract_frontmatter_title(text: str) -> tuple[str, int]:
    """Extract title from YAML front matter. Returns (title, content_start_index)."""
    if not text.startswith("---"):
        return _extract_h1_title(text)

    end = text.find("\n---", 3)
    if end == -1:
        return _extract_h1_title(text)

    frontmatter = text[3:end]
    content_start = end + 4

    for line in frontmatter.splitlines():
        if line.startswith("title:"):
            title = line[6:].strip().strip('"').strip("'")
            return title, content_start

    return _extract_h1_title(text[content_start:])


def _extract_h1_title(text: str) -> tuple[str, int]:
    """Fallback: extract title from first H1 heading."""
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if match:
        return match.group(1).strip(), match.end()
    lines = text.splitlines()
    return lines[0].strip() if lines else "Untitled", len(text)


def _parse_plaintext_blocks(text: str) -> tuple[str, list[ContentBlock]]:
    """Plain text: first line is title, rest is one text block."""
    lines = text.splitlines()
    title = lines[0].strip() if lines else "Untitled"
    body = "\n".join(lines[1:]).strip()
    blocks = [ContentBlock(type="text", content=body)] if body else []
    return title, blocks
