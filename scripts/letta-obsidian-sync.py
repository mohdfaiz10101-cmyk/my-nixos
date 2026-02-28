#!/usr/bin/env python3
"""
Letta → Obsidian 双向同步脚本
功能：
1. 从 Letta 导出 core memory + archival memory
2. 转换为 Obsidian markdown 格式（带 YAML frontmatter）
3. 自动分类、打标签
4. 记录操作日志
"""
import json
import os
from datetime import datetime
from pathlib import Path

LETTA_URL = "http://127.0.0.1:8283/v1"
LETTA_TOKEN = "letta-charlie-2026"
HEADERS = {
    "Authorization": f"Bearer {LETTA_TOKEN}",
    "Content-Type": "application/json",
}
OBSIDIAN_VAULT = Path.home() / "Documents" / "Obsidian" / "Letta-Memory"
OBSIDIAN_VAULT.mkdir(parents=True, exist_ok=True)

def get_letta_agents():
    import subprocess
    try:
        result = subprocess.run(
            ["curl", "-s", f"{LETTA_URL}/agents/",
             "-H", f"Authorization: Bearer {LETTA_TOKEN}"],
            capture_output=True, text=True, timeout=5
        )
        if not result.stdout.strip():
            return []
        data = json.loads(result.stdout)
        return data if isinstance(data, list) else []
    except Exception as e:
        print(f"⚠️  获取 agents 失败: {e}")
        return []

def get_agent_memory(agent_id, agent_name):
    import subprocess
    try:
        # Core memory
        result = subprocess.run(
            ["curl", "-s", f"{LETTA_URL}/agents/{agent_id}/core-memory",
             "-H", f"Authorization: Bearer {LETTA_TOKEN}"],
            capture_output=True, text=True, timeout=5
        )
        core = json.loads(result.stdout) if result.stdout.strip() else {}
        blocks = core.get("blocks", []) if isinstance(core, dict) else []

        # Archival memory
        result = subprocess.run(
            ["curl", "-s", f"{LETTA_URL}/agents/{agent_id}/archival-memory?limit=100",
             "-H", f"Authorization: Bearer {LETTA_TOKEN}"],
            capture_output=True, text=True, timeout=5
        )
        archival = json.loads(result.stdout) if result.stdout.strip() else []
        memories = archival if isinstance(archival, list) else []

        return {"blocks": blocks, "memories": memories}
    except Exception as e:
        print(f"⚠️  获取 {agent_name} 记忆失败: {e}")
        return {"blocks": [], "memories": []}

def memory_to_markdown(agent_name, agent_id, memory_data):
    """转换为 Obsidian markdown 格式"""
    blocks = memory_data.get("blocks", [])
    memories = memory_data.get("memories", [])

    md = f"""---
agent: {agent_name}
agent_id: {agent_id}
type: letta-memory
updated: {datetime.now().isoformat()}
tags: [letta, memory, {agent_name.lower().replace(' ', '-')}]
---

# {agent_name} Memory

> 最后更新: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Core Memory

"""

    for block in blocks:
        label = block.get("label", "?")
        value = block.get("value", "").strip()
        if value:
            md += f"""### {label}

{value}

"""

    md += f"""## Archival Memory ({len(memories)} 条)

"""

    for idx, item in enumerate(memories[:100], 1):
        text = item.get("text", "") if isinstance(item, dict) else str(item)
        md += f"""### [{idx}] 记忆条目

{text}

---

"""
    return md

def sync_to_obsidian():
    """同步到 Obsidian"""
    log_file = OBSIDIAN_VAULT / "sync-log.md"

    agents = get_letta_agents()
    if not agents:
        print("⚠️  未找到 Letta agents")
        return

    log_entries = []

    for agent in agents:
        agent_id = agent.get('id')
        agent_name = agent.get('name', 'unknown')

        memory_data = get_agent_memory(agent_id, agent_name)
        md_content = memory_to_markdown(agent_name, agent_id, memory_data)

        output_file = OBSIDIAN_VAULT / f"{agent_name}.md"
        output_file.write_text(md_content, encoding='utf-8')

        archival_count = len(memory_data.get("memories", []))
        log_entries.append(f"- [{datetime.now().strftime('%H:%M:%S')}] **{agent_name}**: {archival_count} 条记忆 → {output_file.name}")
        print(f"✓ {agent_name}: {archival_count} 条记忆")

    # 更新同步日志
    if log_entries:
        log_content = f"""# Letta 同步日志

最后同步: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## 最近同步记录

{''.join(log_entries)}

"""
        log_file.write_text(log_content, encoding='utf-8')

    # 生成索引文件
    index_md = f"""# Letta Memory Index

更新时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Agents

"""
    for agent in agents:
        agent_name = agent.get('name', 'unknown')
        index_md += f"- [[{agent_name}]]\n"

    (OBSIDIAN_VAULT / "INDEX.md").write_text(index_md, encoding='utf-8')

def main():
    print("🔄 Letta → Obsidian 同步开始...")
    print(f"   目标: {OBSIDIAN_VAULT}")
    sync_to_obsidian()
    print("✓ 同步完成!")

if __name__ == "__main__":
    main()
