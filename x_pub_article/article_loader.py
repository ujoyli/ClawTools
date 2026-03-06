"""
Article content loader for Twitter publisher.

Supports loading articles from:
1. Markdown files (.md) — extracts title from front matter or first H1
2. Plain text files — first line becomes the title, rest is the body

Returns (title, body) tuple where body is plain text suitable for Twitter.
"""

import re
from pathlib import Path


def load_article_content(filepath: str) -> tuple[str, str]:
    """
    Load article title and body from a file.

    For markdown files, extracts the YAML front matter title and
    converts the body to readable plain text (strips markdown syntax).
    """
    text = Path(filepath).read_text(encoding="utf-8")

    if filepath.endswith(".md"):
        return _parse_markdown(text)
    return _parse_plaintext(text)


def _parse_markdown(text: str) -> tuple[str, str]:
    """Parse a markdown file, extracting title and clean body text."""
    title, body_start = _extract_frontmatter_title(text)
    remaining = text[body_start:]

    # Remove first H1 heading if it duplicates the title
    remaining = re.sub(r"^#\s+.+\n", "", remaining, count=1)
    # Remove italic subtitle line
    remaining = re.sub(r"^\*.+\*\n", "", remaining, count=1)

    body = _markdown_to_plain(remaining)
    body = _truncate_to_twitter_limit(body)

    return title, body


def _extract_frontmatter_title(text: str) -> tuple[str, int]:
    """Extract title from YAML front matter block. Returns (title, content_start_index)."""
    if not text.startswith("---"):
        return _extract_h1_title(text)

    end = text.find("\n---", 3)
    if end == -1:
        return _extract_h1_title(text)

    frontmatter = text[3:end]
    content_start = end + 4  # skip closing ---\n

    for line in frontmatter.splitlines():
        if line.startswith("title:"):
            title = line[6:].strip().strip('"').strip("'")
            return title, content_start

    return _extract_h1_title(text[content_start:])


def _extract_h1_title(text: str) -> tuple[str, int]:
    """Extract title from the first H1 heading."""
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if match:
        return match.group(1).strip(), match.end()
    lines = text.splitlines()
    return lines[0].strip() if lines else "Untitled", len(text)


def _markdown_to_plain(md: str) -> str:
    """Convert markdown to plain text suitable for Twitter article body."""
    # Remove image tags
    text = re.sub(r"!\[.*?\]\(.*?\)", "", md)
    # Convert links to text only
    text = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", text)
    # Remove HTML tags
    text = re.sub(r"<[^>]+>", "", text)
    # Remove bold/italic markers
    text = re.sub(r"\*{1,3}([^\*]+)\*{1,3}", r"\1", text)
    text = re.sub(r"_{1,3}([^_]+)_{1,3}", r"\1", text)
    # Convert headings to plain text with newlines
    text = re.sub(r"^#{1,6}\s+(.+)$", r"\n\1\n", text, flags=re.MULTILINE)
    # Remove horizontal rules
    text = re.sub(r"^[-*_]{3,}\s*$", "\n", text, flags=re.MULTILINE)
    # Normalize blockquotes
    text = re.sub(r"^>\s*", "", text, flags=re.MULTILINE)
    # Remove inline code backticks (keep content)
    text = re.sub(r"`{1,3}([^`]+)`{1,3}", r"\1", text)
    # Collapse multiple blank lines
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _truncate_to_twitter_limit(body: str, max_chars: int = 25000) -> str:
    """
    Truncate body to stay within Twitter article limits.

    Twitter articles support up to ~25,000 characters of body text.
    """
    if len(body) <= max_chars:
        return body
    truncated = body[:max_chars]
    # Cut at last paragraph boundary
    last_break = truncated.rfind("\n\n")
    if last_break > max_chars * 0.8:
        truncated = truncated[:last_break]
    return truncated + "\n\n[...]"


def _parse_plaintext(text: str) -> tuple[str, str]:
    """Parse a plain text file: first line = title, rest = body."""
    lines = text.splitlines()
    title = lines[0].strip() if lines else "Untitled"
    body = "\n".join(lines[1:]).strip()
    return title, body
