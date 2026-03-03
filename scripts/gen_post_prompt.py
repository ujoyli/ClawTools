#!/usr/bin/env python3
"""Generate post prompt from template. Usage: python3 gen_post_prompt.py <source_text>"""
import sys

source_text = sys.argv[1] if len(sys.argv) > 1 else ""
template = open("/root/.openclaw/workspace/prompts/x_post_prompt.txt", "r").read()
prompt = template.replace("{SOURCE_TEXT}", source_text[:500])
print(prompt)
