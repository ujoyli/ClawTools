#!/usr/bin/env python3
import os
import re
import json
import time
import random
import subprocess
import shlex
from pathlib import Path
from datetime import datetime, timezone

WORKSPACE = Path('/root/.openclaw/workspace')
STATE_DIR = WORKSPACE / '.openclaw' / 'twitter-hot-reply'
STATE_FILE = STATE_DIR / 'state.json'
LOG_FILE = STATE_DIR / 'run.log'
ENV_FILE = Path.home() / '.config' / 'x-twitter' / '.env'

KEYWORDS = [
    'AI', 'OpenAI', 'GPT-5', 'Claude', 'Gemini',
    'Bitcoin', 'Ethereum', 'Tesla', 'iPhone', 'NVIDIA',
    'startup', 'SaaS', 'indie hacker', 'product launch'
]

# 每次最多回复条数，避免过猛触发风控
MAX_REPLIES_PER_RUN = 2
# 同一条不重复回复
MAX_REPLIED_IDS_KEEP = 5000

REPLY_TEMPLATES = [
    "Strong point. The biggest unlock is execution quality in production: reliability, feedback loops, and measurable user impact.",
    "This trend matters because it shifts from hype to outcomes. Teams that can ship fast and validate with real users will win.",
    "Great signal. The edge now is not just model capability, but how quickly people turn it into repeatable workflows.",
    "很认同这个方向。真正拉开差距的不是概念，而是落地质量：稳定性、反馈闭环和可复用流程。",
    "这条很有价值。下一步关键是把讨论变成可执行方案，并用真实业务指标验证效果。",
]


def sh(cmd: str) -> tuple[int, str, str]:
    p = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    return p.returncode, p.stdout, p.stderr


def load_env():
    if not ENV_FILE.exists():
        raise RuntimeError(f'env file not found: {ENV_FILE}')
    for line in ENV_FILE.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        os.environ[k.strip()] = v.strip().strip('"').strip("'")


def load_state():
    if not STATE_FILE.exists():
        return {"replied_ids": [], "last_run": None}
    try:
        return json.loads(STATE_FILE.read_text(encoding='utf-8'))
    except Exception:
        return {"replied_ids": [], "last_run": None}


def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state['replied_ids'] = state.get('replied_ids', [])[-MAX_REPLIED_IDS_KEEP:]
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')


def log(msg: str):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')
    with LOG_FILE.open('a', encoding='utf-8') as f:
        f.write(f'[{ts}] {msg}\n')


def parse_results(text: str):
    # blocks split by ---
    blocks = [b.strip() for b in text.split('---') if 'ID:' in b]
    items = []
    for b in blocks:
        # first line: user (@handle) · time
        lines = [x.strip() for x in b.splitlines() if x.strip()]
        if len(lines) < 3:
            continue

        header = lines[0]
        content = lines[1]
        metrics_line = next((x for x in lines if '❤️' in x and '🔁' in x), '')
        id_line = next((x for x in lines if x.startswith('ID:')), '')

        m_id = re.search(r'ID:\s*(\d+)', id_line)
        if not m_id:
            continue
        tweet_id = m_id.group(1)

        # likes/retweets/comments/bookmarks
        def metric(icon):
            m = re.search(re.escape(icon) + r'\s*([\d,]+)', metrics_line)
            return int(m.group(1).replace(',', '')) if m else 0

        likes = metric('❤️')
        rts = metric('🔁')
        comments = metric('💬')
        bms = metric('🔖')

        # time priority: if header contains like "2h" or "1h"
        recent2h = False
        hm = re.search(r'\b(\d+)h\b', header)
        if hm and int(hm.group(1)) <= 2:
            recent2h = True

        score = likes + (rts * 2) + (comments * 2) + (bms * 1)
        if recent2h:
            score = int(score * 1.5)

        items.append({
            'id': tweet_id,
            'header': header,
            'text': content,
            'likes': likes,
            'rts': rts,
            'comments': comments,
            'bookmarks': bms,
            'score': score,
            'recent2h': recent2h,
        })
    return items


def collect_candidates():
    all_items = {}
    for kw in KEYWORDS:
        cmd = f'twclaw search "{kw}" --popular --recent -n 8'
        code, out, err = sh(cmd)
        if code != 0:
            log(f'search failed kw={kw}: {err.strip()}')
            continue
        for it in parse_results(out):
            prev = all_items.get(it['id'])
            if not prev or it['score'] > prev['score']:
                all_items[it['id']] = it
    return list(all_items.values())


def craft_reply(item):
    base = random.choice(REPLY_TEMPLATES)
    # 避免机械重复，拼一点针对性
    if any(k in item['text'].lower() for k in ['gpt', 'ai', 'model', 'reasoning']):
        suffix = ' Real differentiator: consistent quality under real user constraints.'
    elif any(k in item['text'].lower() for k in ['bitcoin', 'ethereum', 'crypto']):
        suffix = ' Signal is strong, but risk management and timing still decide outcomes.'
    else:
        suffix = ' The best opportunities come from fast validation + tight iteration.'

    msg = (base + suffix).strip()
    # X 280 chars保守控制
    return msg[:275]


def main():
    load_env()

    # 基础校验
    code, out, err = sh('twclaw auth-check')
    if code != 0:
        log(f'auth-check failed: {err.strip() or out.strip()}')
        return 1

    state = load_state()
    replied = set(state.get('replied_ids', []))

    items = collect_candidates()
    if not items:
        log('no candidates')
        state['last_run'] = int(time.time())
        save_state(state)
        return 0

    # 优先2h内 + 高分
    items.sort(key=lambda x: (x['recent2h'], x['score']), reverse=True)

    posted = 0
    for it in items:
        if posted >= MAX_REPLIES_PER_RUN:
            break
        if it['id'] in replied:
            continue

        reply_text = craft_reply(it)
        cmd = f"twclaw reply {it['id']} {shlex.quote(reply_text)}"
        code, out, err = sh(cmd)
        if code == 0:
            posted += 1
            replied.add(it['id'])
            log(f"replied id={it['id']} score={it['score']} recent2h={it['recent2h']}")
        else:
            log(f"reply failed id={it['id']}: {err.strip() or out.strip()}")

    state['replied_ids'] = list(replied)
    state['last_run'] = int(time.time())
    save_state(state)
    log(f'run done. candidates={len(items)} posted={posted}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
