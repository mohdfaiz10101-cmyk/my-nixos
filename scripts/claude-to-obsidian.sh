#!/usr/bin/env bash
# 自动提取 Claude Code 对话 → 保存到 Obsidian
# 提取用户问题和 Claude 回答，按会话保存为 Markdown
set -euo pipefail

CLAUDE_DIR="/root/.claude/projects"
OBSIDIAN_DIR="/home/charlie/Documents/Obsidian/Claude-Sessions"
LAST_SYNC="/var/lib/nixos-safe-upgrade/claude-obsidian-last-sync"

mkdir -p "$OBSIDIAN_DIR"

# Python 脚本提取对话
python3 - "$CLAUDE_DIR" "$OBSIDIAN_DIR" "$LAST_SYNC" << 'PYEOF'
import json, sys, os, glob
from datetime import datetime
from pathlib import Path

claude_dir = sys.argv[1]
obsidian_dir = sys.argv[2]
last_sync_file = sys.argv[3]

# 读取上次同步时间
last_sync = 0
if os.path.exists(last_sync_file):
    with open(last_sync_file) as f:
        last_sync = float(f.read().strip() or 0)

sessions_saved = 0

# 遍历所有会话 JSONL 文件
for jsonl_file in glob.glob(f"{claude_dir}/**/*.jsonl", recursive=True):
    if "subagent" in jsonl_file:
        continue

    # 跳过旧文件
    mtime = os.path.getmtime(jsonl_file)
    if mtime <= last_sync:
        continue

    session_id = Path(jsonl_file).stem
    messages = []

    try:
        with open(jsonl_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue

                msg_type = msg.get("type", "")
                if msg_type not in ("user", "assistant"):
                    continue

                inner = msg.get("message", {})
                role = inner.get("role", msg_type)
                content = inner.get("content", "")

                if isinstance(content, list):
                    text_parts = [p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text"]
                    content = "\n".join(text_parts)

                # 过滤系统消息和命令输出
                if not content or len(content) < 10:
                    continue
                if content.startswith("<local-command") or content.startswith("<command-"):
                    continue

                if role == "user":
                    messages.append(("user", content[:2000]))
                elif role == "assistant":
                    messages.append(("assistant", content[:3000]))
    except Exception as e:
        continue

    if len(messages) < 2:
        continue

    # 生成 Obsidian Markdown
    timestamp = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
    date_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")

    # 从第一条用户消息提取标题
    first_user = next((m[1][:60] for m in messages if m[0] == "user"), "untitled")
    title = first_user.replace("\n", " ").replace("/", "-").replace(":", "-")

    md_content = f"""---
session: {session_id}
date: {timestamp}
source: claude-code
tags: [claude, conversation]
---

# Claude Code Session — {title}

"""
    for role, content in messages[:50]:  # 限制最多50条
        if role == "user":
            md_content += f"## 🧑 User\n\n{content}\n\n"
        else:
            md_content += f"## 🤖 Claude\n\n{content}\n\n---\n\n"

    # 保存
    safe_id = session_id[:8]
    out_file = f"{obsidian_dir}/{date_str}-{safe_id}.md"
    with open(out_file, 'w') as f:
        f.write(md_content)
    sessions_saved += 1

# 更新同步时间
import time
with open(last_sync_file, 'w') as f:
    f.write(str(time.time()))

print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] Claude → Obsidian: {sessions_saved} sessions synced")
PYEOF

# 修复文件权限让 charlie 能读
chown -R charlie:users "$OBSIDIAN_DIR" 2>/dev/null || true
