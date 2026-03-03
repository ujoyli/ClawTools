import json
import sys
import subprocess

with open("/root/.openclaw/workspace/data/douyin_video_queue.json", "r") as f:
    data = json.load(f)

# Get the last added video
pending = [item for item in data["queue"] if item["status"] == "pending"]
if not pending:
    print("No pending videos")
    sys.exit(1)

video = pending[-1] # The one I just added
title = video["title"]
url = video["url"]

tweet_text = f"{title}\n\n来源：{url}\n#抖音热点"
msg = f"【视频推送审核】\n原视频链接：{url}\n文案：\n{tweet_text}"

print(f"Drafting message to discord: {msg}")
subprocess.run(['openclaw', 'message', 'send', '--channel', 'discord', '--target', 'channel:1476191544808837192', '--message', msg], check=False)
