#!/usr/bin/env bash
# NixOS 测试系统：自动备份 + 大通知界面确认
# 在 nixos-test 前自动备份，测试后定时弹出确认窗口
set -euo pipefail

STATE_DIR="/var/lib/nixos-safe-upgrade"
BACKUP_DIR="/mnt/data/nixos-backups"
mkdir -p "$STATE_DIR" "$BACKUP_DIR"

cmd="${1:-notify}"

case "$cmd" in
  pre-test)
    # 测试前自动备份
    echo "=== 自动备份当前配置 ==="
    ts=$(date '+%Y%m%d-%H%M')
    tar czf "$BACKUP_DIR/pre-test-${ts}.tar.gz" \
      --exclude=node_modules --exclude=result --exclude=.git \
      -C /etc nixos 2>/dev/null || true
    echo "✓ 备份完成: $BACKUP_DIR/pre-test-${ts}.tar.gz"

    # 记录当前稳定版
    bash /etc/nixos/scripts/pin-stable-generation.sh pin
    ;;

  notify)
    # 弹出大通知 — 用 zenity（KDE/GNOME 通用）
    if [ ! -f "$STATE_DIR/test-started" ]; then
      echo "没有测试中的配置。"
      exit 0
    fi

    test_start=$(cat "$STATE_DIR/test-started")
    now=$(date +%s)
    elapsed_days=$(( (now - test_start) / 86400 ))
    elapsed_hours=$(( (now - test_start) / 3600 ))

    # 尝试 zenity（图形界面）
    if command -v zenity &>/dev/null; then
      choice=$(zenity --question \
        --title="⚠️ NixOS 测试系统确认" \
        --text="<b><big>NixOS 测试配置状态</big></b>\n\n测试已运行: <b>${elapsed_hours} 小时 (${elapsed_days} 天)</b>\n建议测试期: 3 天\n\n<b>选择操作：</b>" \
        --ok-label="✅ 确认应用到主系统" \
        --cancel-label="❌ 回滚到稳定版" \
        --extra-button="⏳ 继续测试" \
        --width=500 --height=250 2>&1) && action="confirm" || action="$?"

      case "$choice" in
        "⏳ 继续测试")
          echo "继续测试。"
          notify-send -u normal "NixOS" "继续测试模式 (${elapsed_days}天)"
          ;;
        *)
          if [ "$action" = "confirm" ]; then
            bash /etc/nixos/scripts/nixos-safe-upgrade.sh confirm
            zenity --info --title="NixOS" --text="✅ 配置已正式应用到主系统！" --width=400
          else
            bash /etc/nixos/scripts/nixos-safe-upgrade.sh rollback
            zenity --info --title="NixOS" --text="↩️ 已回滚到稳定版。重启生效。" --width=400
          fi
          ;;
      esac
    else
      # 无图形界面，用终端通知
      echo ""
      echo "╔══════════════════════════════════════════════════╗"
      echo "║       ⚠️  NixOS 测试系统确认                    ║"
      echo "║                                                  ║"
      echo "║  测试已运行: ${elapsed_hours} 小时 (${elapsed_days} 天)              ║"
      echo "║  建议测试期: 3 天                                ║"
      echo "║                                                  ║"
      echo "║  [1] ✅ 确认应用到主系统                        ║"
      echo "║  [2] ❌ 回滚到稳定版                            ║"
      echo "║  [3] ⏳ 继续测试                                ║"
      echo "╚══════════════════════════════════════════════════╝"
      echo ""
      read -p "选择 [1/2/3]: " -r choice
      case "$choice" in
        1) bash /etc/nixos/scripts/nixos-safe-upgrade.sh confirm ;;
        2) bash /etc/nixos/scripts/nixos-safe-upgrade.sh rollback ;;
        *) echo "继续测试。" ;;
      esac
    fi
    ;;
esac
