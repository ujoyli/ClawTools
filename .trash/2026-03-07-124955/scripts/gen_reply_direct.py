#!/usr/bin/env python3
"""Generate reply using direct model API call (bypasses agent system)."""
import sys
import json
import requests

API_KEY = "sk-sp-083dd11c924345a7b8e4c75a56ea58fd"
API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
MODEL = "qwen3.5-plus"

handle = sys.argv[1] if len(sys.argv) > 1 else "?"
tweet_text = sys.argv[2] if len(sys.argv) > 2 else ""

prompt = f"""你是一个真人推特用户，刚刷到一条推文，写一段有观点的评论。

原推文作者：@{handle}
原推文内容：
{tweet_text}

## 硬性规则
1. 长度 10-60 字（必须严格遵守）
2. 像真人评论，不要官话，不要模板腔
3. 需要有引爆点：反差/吐槽/使坏/夸大/调侃/震惊等情绪
4. 如果原推文是中文就用中文，英文就用英文
5. 不要提你是 AI

## 绝对禁止
- 总结式评论、分析式评论、教科书语气
- 系统状态、当前状态、任务状态等词汇
- 任何解释性文字、后续计划、询问用户
- 不要包含问号

## 正确示例
输入：@elonmusk - "SpaceX just launched another Starship"
输出：又炸了一枚？没事，下次再来。

输入：@naval - "The best job is the one you don't have to apply for."
输出：所以现在我天天投简历是在干嘛😅

# 只输出回复文本本身，不要任何其他内容"""

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

payload = {
    "model": MODEL,
    "messages": [
        {"role": "user", "content": prompt}
    ],
    "max_tokens": 100,
    "temperature": 0.8
}

try:
    response = requests.post(API_URL, headers=headers, json=payload, timeout=30)
    response.raise_for_status()
    result = response.json()
    reply = result.get("choices", [{}])[0].get("message", {}).get("content", "").strip()
    
    # Clean up any markdown or extra formatting
    reply = reply.replace("**", "").replace("##", "").strip()
    
    # Output as JSON
    print(json.dumps({"ok": True, "text": reply, "model": MODEL}))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
    sys.exit(1)
