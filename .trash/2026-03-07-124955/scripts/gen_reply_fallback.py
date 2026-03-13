#!/usr/bin/env python3
"""Generate reply using template fallbacks when agent fails."""
import sys
import random

handle = sys.argv[1] if len(sys.argv) > 1 else "?"
tweet_text = sys.argv[2] if len(sys.argv) > 2 else ""

# Simple template-based replies for fallback
templates = [
    f"这操作我是没想到的😂",
    f"真实了",
    f"笑死，太真实了",
    f"这也能行？",
    f"学到了",
    f"确实是这样",
    f"有道理",
    f"细品",
    f"典中典",
    f"这不就是现状吗",
    f"太对了",
    f"无法反驳",
    f"精辟",
    f"扎心了",
    f"真相了",
    f"一语中的",
    f"说到点子上了",
    f"就是这个理",
    f"没毛病",
    f"确实",
]

# Pick a random template
reply = random.choice(templates)
print(reply)
