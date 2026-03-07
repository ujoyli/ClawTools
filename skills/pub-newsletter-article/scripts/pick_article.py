"""
Article picker for pub-newsletter-article skill.

Scans the articles/ directory, loads posted.json, and returns
one unposted article chosen at random.
"""

import json
import os
import random
import sys
from pathlib import Path
from typing import Optional


def load_posted(state_file: Path) -> set[str]:
    """Load the set of already-posted article slugs."""
    if not state_file.exists():
        return set()
    with open(state_file, encoding="utf-8") as f:
        data = json.load(f)
    return {entry["slug"] if isinstance(entry, dict) else entry for entry in data}


def pick_article(articles_dir: Path, state_file: Path) -> Optional[dict]:
    """
    Pick a random unposted article from articles_dir.

    Returns dict with keys: slug, title, article_md, images_dir
    or None if all articles have been posted.
    """
    posted = load_posted(state_file)
    candidates = []

    for article_dir in sorted(articles_dir.iterdir()):
        if not article_dir.is_dir():
            continue
        slug = article_dir.name
        if slug in posted:
            continue
        md_file = article_dir / "article.md"
        if not md_file.exists():
            continue
        candidates.append({"slug": slug, "md_file": md_file, "dir": article_dir})

    if not candidates:
        return None

    chosen = random.choice(candidates)
    title = _extract_title(chosen["md_file"])
    return {
        "slug": chosen["slug"],
        "title": title,
        "article_md": str(chosen["md_file"]),
        "images_dir": str(chosen["dir"] / "images"),
    }


def _extract_title(md_file: Path) -> str:
    """Extract title from YAML front matter or first H1."""
    text = md_file.read_text(encoding="utf-8")
    for line in text.splitlines()[:20]:
        if line.startswith("title:"):
            return line[6:].strip().strip('"').strip("'")
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return md_file.parent.name


def mark_posted(state_file: Path, slug: str, title: str, tweet_url: str) -> None:
    """Append a new entry to the posted.json record."""
    from datetime import datetime, timezone
    records = []
    if state_file.exists():
        with open(state_file, encoding="utf-8") as f:
            records = json.load(f)

    records.append({
        "slug": slug,
        "title": title,
        "tweet_url": tweet_url,
        "posted_at": datetime.now(timezone.utc).isoformat(),
    })

    with open(state_file, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    # Usage:
    #   pick:  python pick_article.py <articles_dir> <state_file>
    #   mark:  python pick_article.py mark <state_file> <slug> <title> <article_url>
    if len(sys.argv) >= 2 and sys.argv[1] == "mark":
        _, _, state, slug, title, url = sys.argv[:6]
        mark_posted(Path(state), slug, title, url)
        print(json.dumps({"ok": True, "slug": slug}))
    else:
        articles_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("articles")
        state_file = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("state/posted.json")
        result = pick_article(articles_dir, state_file)
        print(json.dumps(result or {}, ensure_ascii=False, indent=2))
