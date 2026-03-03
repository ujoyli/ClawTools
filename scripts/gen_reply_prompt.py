#!/usr/bin/env python3
"""Generate reply prompt from template. Usage: python3 gen_reply_prompt.py <handle> <tweet_text>"""
import sys

handle = sys.argv[1] if len(sys.argv) > 1 else "?"
tweet_text = sys.argv[2] if len(sys.argv) > 2 else ""

template = open("/root/.openclaw/workspace/prompts/x_reply_prompt.txt", "r").read()
prompt = template.replace("{HANDLE}", handle).replace("{TWEET_TEXT}", tweet_text[:400])
print(prompt)
