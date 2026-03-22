#!/usr/bin/env bash
# 系统健康监控：磁盘空间 + 自动备份 + 3天状态追踪
# 每天运行一次（systemd timer）
set -euo pipefail

STATE_DIR="/var/lib/nixos-safe-upgrade"
BACKUP_DIR="/mnt/data/nixos-backups"
LOG_FILE="$STATE_DIR/health.log"
mkdir -p "$STATE_DIR" "$BACKUP_DIR" 2>/dev/null || true

log() { echo "[$(date '+%Y-%m-%d %H:%M')] $*" | tee -a "$LOG_FILE"; }

# === 1. 磁盘空间检查 ===
root_usage=$(df / --output=pcent | tail -1 | tr -d ' %')
efi_usage=$(df /boot/efi --output=pcent | tail -1 | tr -d ' %')
nix_size=$(du -sh /nix/store 2>/dev/null | cut -f1)

log "磁盘: / ${root_usage}%, /boot/efi ${efi_usage}%, /nix/store ${nix_size}"

if [ "$root_usage" -gt 85 ]; then
  log "⚠️ 根分区 ${root_usage}% > 85%！自动清理旧 generations..."
  # 恢复稳定版 pin（如果有的话）
  bash /etc/nixos/scripts/pin-stable-generation.sh restore 2>/dev/null || true
  nix-collect-garbage --delete-older-than 3d 2>/dev/null || true
  bash /etc/nixos/scripts/pin-stable-generation.sh restore 2>/dev/null || true
  new_usage=$(df / --output=pcent | tail -1 | tr -d ' %')
  log "清理后: / ${new_usage}%"
fi

if [ "$efi_usage" -gt 80 ]; then
  log "⚠️ EFI 分区 ${efi_usage}% > 80%！configurationLimit=3 应该能控制"
fi

# === 2. 每日配置备份（保留 3 天，双备份）===
today=$(date '+%Y-%m-%d')
backup_file="$BACKUP_DIR/nixos-config-${today}.tar.gz"

if [ ! -f "$backup_file" ]; then
  tar czf "$backup_file" \
    --exclude=node_modules \
    --exclude=result \
    --exclude=.git \
    -C /etc nixos 2>/dev/null || true
  log "✓ 配置已备份到 $backup_file"

  # 双备份到 1.8T 外置硬盘（如果挂载了）
  if mountpoint -q /mnt/storage_1.8t 2>/dev/null; then
    mkdir -p /mnt/storage_1.8t/nixos-backups 2>/dev/null || true
    cp "$backup_file" /mnt/storage_1.8t/nixos-backups/ 2>/dev/null || true
    log "✓ 双备份到 /mnt/storage_1.8t/nixos-backups/"
  fi

  # 网盘备份（rclone，如果配置了）
  if command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q .; then
    remote=$(rclone listremotes 2>/dev/null | head -1)
    rclone copy "$backup_file" "${remote}nixos-backups/" 2>/dev/null || true
    log "✓ 网盘备份到 ${remote}nixos-backups/"
  fi
fi

# 清理 3 天前的备份
find "$BACKUP_DIR" -name "nixos-config-*.tar.gz" -mtime +3 -delete 2>/dev/null || true
find /mnt/storage_1.8t/nixos-backups -name "nixos-config-*.tar.gz" -mtime +3 -delete 2>/dev/null || true
log "备份保留: $(ls "$BACKUP_DIR"/nixos-config-*.tar.gz 2>/dev/null | wc -l) 份"

# === 3. 稳定版 GC root 检查 ===
if [ -L /nix/var/nix/gcroots/pinned-stable-system ]; then
  stable_path=$(readlink -f /nix/var/nix/gcroots/pinned-stable-system)
  if [ -d "$stable_path" ]; then
    log "✓ 稳定版 GC root 完好: $stable_path"
  else
    log "⚠️ 稳定版 store path 丢失！需要重新 pin"
  fi
else
  log "⚠️ 没有固定稳定版。运行: pin-stable"
fi

# === 4. 测试模式状态追踪 ===
if [ -f "$STATE_DIR/test-started" ]; then
  test_start=$(cat "$STATE_DIR/test-started")
  now=$(date +%s)
  elapsed_days=$(( (now - test_start) / 86400 ))

  log "测试模式: 已运行 ${elapsed_days} 天"

  if [ "$elapsed_days" -ge 3 ]; then
    log ">>> 测试已超过 3 天！可以运行 nixos-confirm 正式应用"
    # 发送桌面通知（如果有图形界面）
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
      su charlie -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -u critical "NixOS 测试完成" "测试已运行 '"$elapsed_days"' 天，运行 nixos-confirm 正式应用，或 nixos-rollback 回滚"' 2>/dev/null || true
    fi
  fi
fi

log "--- 健康检查完成 ---"
