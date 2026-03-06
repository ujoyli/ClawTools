"""
Cover image generator for Twitter/X articles.

Generates a stylized cover image with the article title as text overlay.
Uses Pillow to draw a gradient background with bold title text.
Output is a PNG at 1500x600 (5:2 ratio, recommended for Twitter articles).
"""

import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
import numpy as np


COVER_WIDTH = 1500
COVER_HEIGHT = 600

# Dark navy gradient colors
COLOR_TOP = (12, 20, 48)       # deep navy
COLOR_BOTTOM = (6, 40, 80)     # dark teal-navy

TEXT_COLOR_TITLE = (255, 255, 255)
TEXT_COLOR_ACCENT = (0, 200, 230)  # cyan accent

FONT_PATH_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def generate_cover_image(title: str, output_path: str) -> None:
    """
    Generate a cover image for a Twitter article.

    Creates a 1500x600 image with a dark gradient background and the
    article title rendered in large bold white text. Saves to output_path.
    """
    img = Image.new("RGB", (COVER_WIDTH, COVER_HEIGHT))
    _draw_gradient(img)
    _draw_decorative_elements(img)
    _draw_title(img, title)
    img.save(output_path, "PNG")


def _draw_gradient(img: Image.Image) -> None:
    """Fill the image with a vertical linear gradient."""
    draw = ImageDraw.Draw(img)
    for y in range(COVER_HEIGHT):
        ratio = y / COVER_HEIGHT
        r = int(COLOR_TOP[0] + (COLOR_BOTTOM[0] - COLOR_TOP[0]) * ratio)
        g = int(COLOR_TOP[1] + (COLOR_BOTTOM[1] - COLOR_TOP[1]) * ratio)
        b = int(COLOR_TOP[2] + (COLOR_BOTTOM[2] - COLOR_TOP[2]) * ratio)
        draw.line([(0, y), (COVER_WIDTH, y)], fill=(r, g, b))


def _draw_decorative_elements(img: Image.Image) -> None:
    """Add subtle decorative lines and accents."""
    draw = ImageDraw.Draw(img)
    # Accent line at bottom
    draw.rectangle([(0, COVER_HEIGHT - 8), (COVER_WIDTH, COVER_HEIGHT)], fill=TEXT_COLOR_ACCENT)
    # Subtle diagonal lines for texture
    for x in range(0, COVER_WIDTH + COVER_HEIGHT, 80):
        draw.line([(x, 0), (x - COVER_HEIGHT, COVER_HEIGHT)], fill=(255, 255, 255, 10), width=1)


def _draw_title(img: Image.Image, title: str) -> None:
    """Render the article title centered on the image."""
    draw = ImageDraw.Draw(img)
    font_large = _load_font(120)
    font_small = _load_font(36)

    # Wrap title if too long
    wrapped = textwrap.wrap(title, width=20)
    line_height = 140

    total_height = len(wrapped) * line_height
    y_start = (COVER_HEIGHT - total_height) // 2 - 20

    for i, line in enumerate(wrapped):
        bbox = draw.textbbox((0, 0), line, font=font_large)
        text_w = bbox[2] - bbox[0]
        x = (COVER_WIDTH - text_w) // 2
        y = y_start + i * line_height
        draw.text((x + 3, y + 3), line, font=font_large, fill=(0, 0, 0, 128))  # shadow
        draw.text((x, y), line, font=font_large, fill=TEXT_COLOR_TITLE)

    # Subtitle label
    label = "Tech World with Milan Newsletter"
    bbox = draw.textbbox((0, 0), label, font=font_small)
    label_w = bbox[2] - bbox[0]
    draw.text(
        ((COVER_WIDTH - label_w) // 2, COVER_HEIGHT - 70),
        label,
        font=font_small,
        fill=TEXT_COLOR_ACCENT,
    )


def _load_font(size: int):
    """Load a bold font, falling back to PIL default if system fonts unavailable."""
    for path in FONT_PATH_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()
