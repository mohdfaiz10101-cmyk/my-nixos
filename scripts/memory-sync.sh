#!/usr/bin/env bash
# Letta + 记忆碎片 同步到 Obsidian 的包装脚本

echo "🔄 同步 Letta 记忆到 Obsidian..."
nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/letta-obsidian-sync.py' 2>/dev/null

echo "🔄 整理记忆碎片..."
nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/memory/manage-fragments.py' 2>/dev/null

echo "✅ 同步完成！Obsidian: ~/Documents/Obsidian/"
