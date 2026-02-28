#!/usr/bin/env python3
"""
Letta 记忆同步到 Obsidian
将 core memory + archival memory 导出为 Markdown 文件
"""

import json
import requests
from datetime import datetime
import os
from pathlib import Path

# 配置
LETTA_BASE_URL = "http://127.0.0.1:8283"
OBSIDIAN_VAULT = Path.home() / "Documents" / "Obsidian" / "Letta-Memory"
AGENTS = {
    "nixos-sysadmin": "🖥️ 系统管理",
    "code-assistant": "💻 代码助手",
    "opus-analyst": "🧠 分析专家"
}

def fetch_memories(agent_id):
    """获取 agent 的所有记忆"""
    try:
        # Core memory
        core_resp = requests.get(f"{LETTA_BASE_URL}/agent/{agent_id}/core-memory")
        core_data = core_resp.json() if core_resp.status_code == 200 else {}

        # Archival memory
        archival_resp = requests.get(f"{LETTA_BASE_URL}/agent/{agent_id}/archival-memory")
        archival_data = archival_resp.json() if archival_resp.status_code == 200 else {}

        return {"core": core_data, "archival": archival_data}
    except Exception as e:
        return {"error": str(e)}

def to_obsidian_md(agent_id, agent_name, memories):
    """转换为 Obsidian Markdown 格式"""
    timestamp = datetime.now().isoformat()
    md = f"""---
type: letta-memory
agent: {agent_id}
agent_name: {agent_name}
synced_at: {timestamp}
tags: [letta, {agent_id}, memory]
---

# {agent_name} - 记忆同步

## 最后更新
{timestamp}

## Core Memory

"""

    if "error" in memories:
        md += f"❌ 错误: {memories['error']}\n"
    else:
        core = memories.get("core", {})
        if isinstance(core, dict):
            for key, value in core.items():
                md += f"### {key}\n{value}\n\n"
        elif isinstance(core, list):
            for item in core:
                md += f"- {item}\n"

        md += "\n## Archival Memory\n\n"
        archival = memories.get("archival", {})
        if isinstance(archival, list):
            for item in archival[:50]:  # 限制显示数量
                text = item.get("text", str(item))[:200]
                md += f"- {text}...\n"
        elif isinstance(archival, dict):
            for key, value in list(archival.items())[:20]:
                md += f"### {key}\n{value}\n\n"

    return md

def sync_to_obsidian():
    """同步所有 agent 记忆到 Obsidian"""
    OBSIDIAN_VAULT.mkdir(parents=True, exist_ok=True)

    for agent_id, agent_name in AGENTS.items():
        print(f"🔄 同步 {agent_name}...")
        memories = fetch_memories(agent_id)
        md_content = to_obsidian_md(agent_id, agent_name, memories)

        # 写入 Obsidian
        file_path = OBSIDIAN_VAULT / f"{agent_id}.md"
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(md_content)
        print(f"✅ {agent_name} → {file_path}")

    # 创建索引文件
    index_md = """# Letta 记忆索引

## Agent 列表

"""
    for agent_id, agent_name in AGENTS.items():
        index_md += f"- [{agent_name}]({agent_id}.md)\n"

    index_path = OBSIDIAN_VAULT / "INDEX.md"
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(index_md)
    print(f"✅ 索引文件 → {index_path}")

if __name__ == "__main__":
    sync_to_obsidian()
