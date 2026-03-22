#!/usr/bin/env bash
# 自动备份用户数据到 /mnt/data — 防止重装丢失
# 每天自动运行一次（通过 systemd timer）
set -euo pipefail

BACKUP_DIR="/mnt/data/home-backup"

if ! mountpoint -q /mnt/data; then
  echo "数据盘未挂载，跳过备份"
  exit 0
fi

mkdir -p "$BACKUP_DIR"

# 备份浏览器数据
for dir in .floorp .mozilla .config/google-chrome; do
  if [ -d "$HOME/$dir" ]; then
    mkdir -p "$BACKUP_DIR/$dir"
    rsync -a --delete "$HOME/$dir/" "$BACKUP_DIR/$dir/" 2>/dev/null
    echo "已备份 $dir"
  fi
done

# 备份 IDE 数据
for dir in .config/JetBrains .config/Code .config/cursor; do
  if [ -d "$HOME/$dir" ]; then
    mkdir -p "$BACKUP_DIR/$dir"
    rsync -a --delete "$HOME/$dir/" "$BACKUP_DIR/$dir/" 2>/dev/null
    echo "已备份 $dir"
  fi
done

# 备份 JetBrains cache
if [ -d "$HOME/.cache/JetBrains" ]; then
  mkdir -p "$BACKUP_DIR/.cache/JetBrains"
  rsync -a --delete "$HOME/.cache/JetBrains/" "$BACKUP_DIR/.cache/JetBrains/" 2>/dev/null
fi

# 备份输入法数据
for dir in .local/share/fcitx5 .config/fcitx5; do
  if [ -d "$HOME/$dir" ]; then
    mkdir -p "$BACKUP_DIR/$dir"
    rsync -a --delete "$HOME/$dir/" "$BACKUP_DIR/$dir/" 2>/dev/null
    echo "已备份 $dir"
  fi
done

# 备份 SSH 密钥
if [ -d "$HOME/.ssh" ]; then
  mkdir -p "$BACKUP_DIR/.ssh"
  rsync -a "$HOME/.ssh/" "$BACKUP_DIR/.ssh/" 2>/dev/null
  echo "已备份 .ssh"
fi

echo "备份完成: $(date)"
