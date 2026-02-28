#!/usr/bin/env python3
"""
记忆碎片管理系统
从 Claude history + Letta 收集碎片，自动打标签、归档、导出到 Obsidian
"""

import json
import re
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
import os

# 配置
FRAGMENTS_DIR = Path("/etc/nixos/scripts/memory/fragments")
ARCHIVE_DIR = Path("/etc/nixos/scripts/memory/archive")
OBSIDIAN_DIR = Path.home() / "Documents" / "Obsidian" / "Memory-Fragments"

# 标签规则（关键词 -> 标签）
TAG_RULES = {
    "NixOS": ["nixos", "nix-", "configuration.nix", "flake.nix", "nixos-rebuild"],
    "Docker": ["docker", "container", "compose", "容器"],
    "AI": ["ai", "llm", "claude", "ollama", "litellm", "模型"],
    "Letta": ["letta", "memory", "记忆", "agent"],
    "Git": ["git", "commit", "branch", "merge", "pull", "push"],
    "问题": ["错误", "error", "failed", "问题", "bug", "issue"],
    "修复": ["修复", "fix", "solved", "解决", "patch"],
    "配置": ["配置", "config", "setting", "设置"],
}

# 重要性评分规则
IMPORTANCE_KEYWORDS = {
    "高": ["错误", "error", "failed", "问题", "安全", "important", "critical"],
    "中": ["修复", "fix", "配置", "优化", "update"],
    "低": ["备注", "note", "minor", "trivial"],
}

class MemoryFragment:
    def __init__(self, content, source="", timestamp=None):
        self.content = content
        self.source = source
        self.timestamp = timestamp or datetime.now()
        self.tags = self._extract_tags()
        self.importance = self._calculate_importance()
        self.last_accessed = datetime.now()

    def _extract_tags(self):
        """根据内容自动打标签"""
        tags = []
        content_lower = self.content.lower()
        for tag, keywords in TAG_RULES.items():
            if any(kw in content_lower for kw in keywords):
                tags.append(tag)
        return tags

    def _calculate_importance(self):
        """计算重要性评分 0-10"""
        score = 5  # 默认中等
        for level, keywords in IMPORTANCE_KEYWORDS.items():
            if any(kw in self.content.lower() for kw in keywords):
                if level == "高":
                    score = min(10, score + 3)
                elif level == "中":
                    score = min(8, score + 1)
                else:
                    score = max(1, score - 2)
        return score

    def to_obsidian_md(self):
        """转换为 Obsidian Markdown"""
        tags_str = ", ".join(self.tags) if self.tags else "未分类"
        return f"""---
type: memory-fragment
source: {self.source}
importance: {self.importance}/10
created_at: {self.timestamp.isoformat()}
last_accessed: {self.last_accessed.isoformat()}
tags: [{tags_str}]
---

# 记忆碎片

## 来源
{self.source}

## 重要性
{self.importance}/10

## 标签
{", ".join(self.tags)}

## 内容
{self.content}

---
*最后访问: {self.last_accessed.strftime('%Y-%m-%d %H:%M')}*
"""

class FragmentManager:
    def __init__(self):
        FRAGMENTS_DIR.mkdir(parents=True, exist_ok=True)
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        OBSIDIAN_DIR.mkdir(parents=True, exist_ok=True)
        self.fragments = self._load_fragments()

    def _load_fragments(self):
        """加载所有碎片"""
        fragments = []
        for json_file in FRAGMENTS_DIR.glob("*.json"):
            try:
                with open(json_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    frag = MemoryFragment(
                        data["content"],
                        data.get("source", ""),
                        datetime.fromisoformat(data["timestamp"])
                    )
                    frag.last_accessed = datetime.fromisoformat(data["last_accessed"])
                    fragments.append(frag)
            except Exception as e:
                print(f"⚠️ 加载 {json_file} 失败: {e}")
        return fragments

    def add_fragment(self, content, source="manual"):
        """添加新碎片"""
        frag = MemoryFragment(content, source)
        self.fragments.append(frag)
        self._save_fragment(frag)
        return frag

    def _save_fragment(self, frag):
        """保存碎片到文件"""
        filename = f"{frag.timestamp.strftime('%Y%m%d-%H%M%S')}-{len(frag.tags)}tags.json"
        filepath = FRAGMENTS_DIR / filename
        data = {
            "content": frag.content,
            "source": frag.source,
            "timestamp": frag.timestamp.isoformat(),
            "last_accessed": frag.last_accessed.isoformat(),
            "tags": frag.tags,
            "importance": frag.importance,
        }
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def archive_old_fragments(self, days=30):
        """归档 30 天未访问的碎片"""
        cutoff = datetime.now() - timedelta(days=days)
        archived = 0
        active_fragments = []
        
        for frag in self.fragments:
            if frag.last_accessed < cutoff and frag.importance < 6:
                # 归档低重要性且久未访问的
                self._archive_fragment(frag)
                archived += 1
            else:
                active_fragments.append(frag)
        
        self.fragments = active_fragments
        return archived

    def _archive_fragment(self, frag):
        """归档碎片"""
        archive_path = ARCHIVE_DIR / f"{frag.timestamp.strftime('%Y%m')}.jsonl"
        with open(archive_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "content": frag.content,
                "source": frag.source,
                "archived_at": datetime.now().isoformat(),
            }, ensure_ascii=False) + "\n")

    def export_to_obsidian(self):
        """按标签导出到 Obsidian"""
        # 按标签分组
        by_tag = defaultdict(list)
        for frag in self.fragments:
            for tag in frag.tags or ["未分类"]:
                by_tag[tag].append(frag)

        # 为每个标签创建文件
        for tag, fragments in by_tag.items():
            # 按重要性排序
            fragments.sort(key=lambda f: f.importance, reverse=True)
            
            md = f"""---
type: memory-fragments-by-tag
tag: {tag}
count: {len(fragments)}
synced_at: {datetime.now().isoformat()}
tags: [memory-fragments, {tag}]
---

# {tag} 记忆碎片

共 {len(fragments)} 条记忆碎片

"""
            for frag in fragments[:20]:  # 每个标签最多显示 20 条
                md += f"""
## 重要性 {frag.importance}/10 - {frag.timestamp.strftime('%Y-%m-%d')}

**来源**: {frag.source}

{frag.content[:300]}{'...' if len(frag.content) > 300 else ''}

---
"""

            tag_file = OBSIDIAN_DIR / f"{tag}.md"
            with open(tag_file, "w", encoding="utf-8") as f:
                f.write(md)

        # 创建索引
        index_md = """# 记忆碎片索引

## 按标签浏览

"""
        for tag in sorted(by_tag.keys()):
            count = len(by_tag[tag])
            index_md += f"- [{tag}]({tag}.md) - {count} 条\n"

        index_file = OBSIDIAN_DIR / "INDEX.md"
        with open(index_file, "w", encoding="utf-8") as f:
            f.write(index_md)

        return len(by_tag)

def main():
    """主函数"""
    manager = FragmentManager()
    
    # 归档旧碎片
    archived = manager.archive_old_fragments()
    print(f"📦 归档了 {archived} 条旧碎片")
    
    # 导出到 Obsidian
    tag_count = manager.export_to_obsidian()
    print(f"📝 导出到 Obsidian: {tag_count} 个标签")
    
    # 统计
    print(f"\n📊 当前统计:")
    print(f"   活跃碎片: {len(manager.fragments)}")
    print(f"   标签数: {tag_count}")

if __name__ == "__main__":
    main()
