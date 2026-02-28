#!/usr/bin/env python3
"""
记忆碎片整合系统
功能：
1. 从多个来源收集碎片（Claude history, Letta）
2. 自动分类、打标签
3. 相似内容合并
4. 无用信息归档/删除
5. 多级标签系统
"""
import json
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict
import hashlib
import re

CLAUDE_HISTORY = Path.home() / ".claude" / "history.jsonl"
LETTA_URL = "http://127.0.0.1:8283/v1"
LETTA_TOKEN = "letta-charlie-2026"
OBSIDIAN_VAULT = Path.home() / "Documents" / "Obsidian" / "Memory-Fragments"
ARCHIVE_THRESHOLD = 30  # 30天未访问自动归档

OBSIDIAN_VAULT.mkdir(parents=True, exist_ok=True)

class MemoryFragment:
    def __init__(self, content, source, timestamp, metadata=None):
        self.content = content
        self.source = source
        self.timestamp = timestamp
        self.metadata = metadata or {}
        self.tags = []
        self.importance = 0
        self.hash = hashlib.md5(content.encode()).hexdigest()[:8]

    def to_dict(self):
        return {
            "content": self.content,
            "source": self.source,
            "timestamp": self.timestamp,
            "tags": self.tags,
            "importance": self.importance,
            "hash": self.hash,
            "metadata": self.metadata
        }

def collect_claude_fragments():
    """从 Claude Code history 收集碎片"""
    fragments = []
    if not CLAUDE_HISTORY.exists():
        return fragments

    with open(CLAUDE_HISTORY, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                if 'messages' in entry:
                    for msg in entry['messages']:
                        if msg.get('role') == 'user':
                            content = msg.get('content', '')
                            if len(content) > 20:  # 过滤太短的内容
                                fragments.append(MemoryFragment(
                                    content=content,
                                    source='claude-code',
                                    timestamp=entry.get('timestamp', datetime.now().isoformat()),
                                    metadata={'session_id': entry.get('id')}
                                ))
            except:
                continue
    return fragments

def collect_letta_fragments():
    """从 Letta 收集碎片"""
    fragments = []
    try:
        result = subprocess.run(
            ["curl", "-s", f"{LETTA_URL}/agents/",
             "-H", f"Authorization: Bearer {LETTA_TOKEN}"],
            capture_output=True, text=True, timeout=5
        )
        if not result.stdout.strip():
            return fragments
        agents = json.loads(result.stdout)

        for agent in agents:
            agent_id = agent.get('id')
            agent_name = agent.get('name', 'unknown')
            result = subprocess.run(
                ["curl", "-s", f"{LETTA_URL}/agents/{agent_id}/archival-memory?limit=50",
                 "-H", f"Authorization: Bearer {LETTA_TOKEN}"],
                capture_output=True, text=True, timeout=5
            )
            if result.stdout.strip():
                memories = json.loads(result.stdout)
                for mem in memories[:50]:
                    text = mem.get("text", "") if isinstance(mem, dict) else str(mem)
                    if len(text) > 20:
                        fragments.append(MemoryFragment(
                            content=text,
                            source=f"letta-{agent_name}",
                            timestamp=datetime.now().isoformat(),
                            metadata={'agent_id': agent_id}
                        ))
    except Exception as e:
        print(f"⚠️  Letta 收集失败: {e}")
    return fragments

def auto_tag_fragment(fragment):
    """使用规则自动打标签"""
    content = fragment.content.lower()

    # 技术标签
    tech_tags = []
    if any(kw in content for kw in ['nixos', 'flake', 'configuration']):
        tech_tags.append('NixOS')
    if any(kw in content for kw in ['docker', 'compose', 'container']):
        tech_tags.append('Docker')
    if any(kw in content for kw in ['ai', 'llm', 'model', 'api']):
        tech_tags.append('AI')
    if any(kw in content for kw in ['letta', 'memory', 'agent']):
        tech_tags.append('Letta')
    if any(kw in content for kw in ['git', 'commit', 'branch']):
        tech_tags.append('Git')

    # 类型标签
    if '问题' in content or 'bug' in content or '错误' in content:
        tech_tags.append('问题')
    if '修复' in content or 'fix' in content or '解决' in content:
        tech_tags.append('修复')
    if '配置' in content or 'config' in content:
        tech_tags.append('配置')

    fragment.tags = tech_tags if tech_tags else ['未分类']
    return fragment

def calculate_importance(fragment):
    """计算重要性（0-10）"""
    score = 5
    content = fragment.content

    # 长度加分
    if len(content) > 500:
        score += 2
    if len(content) > 1000:
        score += 1

    # 关键词加分
    important_keywords = ['重要', '关键', '必须', '核心', '注意', 'warning', 'critical']
    for kw in important_keywords:
        if kw in content:
            score += 1
            break

    # 来源加分
    if fragment.source.startswith('letta'):
        score += 1

    fragment.importance = min(score, 10)
    return fragment

def archive_old_fragments(fragments, days=30):
    """归档旧碎片"""
    cutoff = datetime.now() - timedelta(days=days)
    active = []
    archived = []

    for frag in fragments:
        try:
            ts = datetime.fromisoformat(frag.timestamp.replace('Z', '+00:00'))
            if ts < cutoff and frag.importance < 5:
                archived.append(frag)
            else:
                active.append(frag)
        except:
            active.append(frag)

    return active, archived

def export_to_obsidian(fragments):
    """导出到 Obsidian"""
    if not fragments:
        print("⚠️  没有记忆碎片可导出")
        return

    # 按标签分组
    by_tag = defaultdict(list)
    for frag in fragments:
        for tag in frag.tags or ['未分类']:
            by_tag[tag].append(frag)

    # 生成索引文件
    total_fragments = len(fragments)
    total_tags = len(by_tag)

    index_md = f"""---
title: Memory Fragments Index
updated: {datetime.now().isoformat()}
---

# 记忆碎片索引

> 统计：**{total_fragments}** 个碎片，**{total_tags}** 个标签

最后更新: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## 按标签分类

"""

    for tag, frags in sorted(by_tag.items(), key=lambda x: len(x[1]), reverse=True):
        index_md += f"- [[{tag}]] ({len(frags)} 个)\n"

    index_md += f"""

## 统计信息

| 标签 | 数量 |
|------|------|
{''.join([f"| {tag} | {len(frags)} |\n" for tag, frags in sorted(by_tag.items(), key=lambda x: len(x[1]), reverse=True)[:10]])}
"""

    (OBSIDIAN_VAULT / "INDEX.md").write_text(index_md, encoding='utf-8')

    # 生成标签文件
    for tag, frags in sorted(by_tag.items()):
        tag_md = f"""---
tag: {tag}
count: {len(frags)}
updated: {datetime.now().isoformat()}
---

# {tag}

> {len(frags)} 个记忆碎片

"""

        # 按重要性排序，只显示前 50 个
        sorted_frags = sorted(frags, key=lambda x: x.importance, reverse=True)[:50]

        for frag in sorted_frags:
            # 截取内容预览
            preview = frag.content[:300].replace('\n', ' ')
            if len(frag.content) > 300:
                preview += "..."

            tag_md += f"""## [{frag.hash}] {frag.source}

**重要性**: {'⭐' * (frag.importance // 2)} ({frag.importance}/10)
**时间**: {frag.timestamp.split('T')[0]}
**标签**: {', '.join(frag.tags)}

{preview}

---

"""
        (OBSIDIAN_VAULT / f"{tag}.md").write_text(tag_md, encoding='utf-8')

    print(f"✓ Exported {len(fragments)} fragments to {OBSIDIAN_VAULT}")

def main():
    print("🔍 收集记忆碎片...")

    all_fragments = []
    all_fragments.extend(collect_claude_fragments())
    all_fragments.extend(collect_letta_fragments())

    print(f"  收集到 {len(all_fragments)} 个碎片")

    if not all_fragments:
        print("⚠️  没有找到记忆碎片")
        return

    print("🏷️  自动打标签...")
    for frag in all_fragments:
        auto_tag_fragment(frag)
        calculate_importance(frag)

    print("📦 归档旧碎片...")
    active, archived = archive_old_fragments(all_fragments)
    print(f"  活跃: {len(active)}, 归档: {len(archived)}")

    print("📝 导出到 Obsidian...")
    export_to_obsidian(active)

    print("\n✓ 记忆碎片管理完成!")
    print(f"   查看: {OBSIDIAN_VAULT}")

if __name__ == "__main__":
    main()
