#!/usr/bin/env python3
"""Generate reply prompt from template. Usage: python3 gen_reply_prompt.py <handle> <tweet_text>"""
import sys

handle = sys.argv[1] if len(sys.argv) > 1 else "?"
tweet_text = sys.argv[2] if len(sys.argv) > 2 else ""

template = open("/root/.openclaw/workspace/prompts/x_reply_prompt.txt", "r").read()
base = template.replace("{HANDLE}", handle).replace("{TWEET_TEXT}", tweet_text)

skill_prefix = """在写回复前，先加载并遵循这个 skill：/root/.openclaw/workspace/skills/humanizer/SKILL.md\n要求：\n- 去掉 AI 味、宣传腔、套话和机械排比\n- 保留口语感、真人感、情绪和观点\n- 不要解释过程，不要输出分析，只直接给最终回复\n- 回复要像真人在 X 上顺手发的评论，不像客服，不像总结报告\n\n"""

print(skill_prefix + base)
