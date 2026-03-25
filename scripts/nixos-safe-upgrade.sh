#!/usr/bin/env bash
# NixOS 智能安全升级系统：test → 自动观察 → 自动 confirm
# 流程：
#   1. ns / nixos-test → 编译并激活测试配置（不写 GRUB）
#   2. systemd timer 每天检查一次
#   3. 运行满 3 天 + 无崩溃 → 自动 switch 写入 GRUB
#   4. 如果有崩溃记录 → 自动回滚并通知
set -euo pipefail

STABLE_MARKER="/var/lib/nixos-safe-upgrade/stable-generation"
TEST_MARKER="/var/lib/nixos-safe-upgrade/test-started"
CRASH_LOG="/var/lib/nixos-safe-upgrade/crash-detected"
CONFIRM_DAYS=3
STATE_DIR="/var/lib/nixos-safe-upgrade"

mkdir -p "$STATE_DIR"
cmd="${1:-status}"

check_health() {
  local test_start="$1"
  local issues=0
  local report=""
  local crash_count
  crash_count=$(journalctl --since "@$test_start" -p 2 --no-pager -q 2>/dev/null | wc -l)
  if [ "$crash_count" -gt 10 ]; then
    report="$report\n- 严重错误日志: ${crash_count} 条"
    issues=$((issues + 1))
  fi
  for svc in sddm NetworkManager xray; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
      report="$report\n- 关键服务挂掉: $svc"
      issues=$((issues + 1))
    fi
  done
  local oom_count
  oom_count=$(journalctl --since "@$test_start" -k --no-pager -q 2>/dev/null | grep -c "Out of memory" || true)
  if [ "$oom_count" -gt 0 ]; then
    report="$report\n- OOM killer 触发: ${oom_count} 次"
    issues=$((issues + 1))
  fi
  if [ "$issues" -gt 0 ]; then
    echo -e "$report" > "$CRASH_LOG"
    return 1
  fi
  rm -f "$CRASH_LOG"
  return 0
}

notify() {
  local msg="$1"
  local urgency="${2:-normal}"
  if command -v notify-send &>/dev/null; then
    sudo -u charlie DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
      DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 \
      notify-send -u "$urgency" "NixOS 安全升级" "$msg" 2>/dev/null || true
  fi
  echo "[$(date '+%Y-%m-%d %H:%M')] $msg" >> "$STATE_DIR/history.log"
}

case "$cmd" in
  test)
    current_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "$current_gen" > "$STABLE_MARKER"
    date +%s > "$TEST_MARKER"
    rm -f "$CRASH_LOG"
    echo "=== 智能安全测试模式 ==="
    echo "当前稳定版: generation $current_gen"
    echo "正在编译并激活测试配置..."
    sudo nixos-rebuild test --flake /etc/nixos#charlie
    echo ""
    echo "✓ 测试配置已激活！"
    echo "  - 重启 = 自动回到稳定版"
    echo "  - ${CONFIRM_DAYS} 天无崩溃 → 自动正式应用"
    echo "  - 有崩溃 → 自动回滚并通知"
    notify "测试配置已激活，${CONFIRM_DAYS} 天后自动确认"
    ;;
  auto-confirm)
    if [ ! -f "$TEST_MARKER" ]; then exit 0; fi
    test_start=$(cat "$TEST_MARKER")
    now=$(date +%s)
    elapsed_days=$(( (now - test_start) / 86400 ))
    if [ "$elapsed_days" -lt "$CONFIRM_DAYS" ]; then
      remaining=$(( CONFIRM_DAYS - elapsed_days ))
      notify "测试中：还需观察 ${remaining} 天"
      exit 0
    fi
    if ! check_health "$test_start"; then
      notify "检测到系统异常，自动回滚！" "critical"
      if [ -f "$STABLE_MARKER" ]; then
        stable_gen=$(cat "$STABLE_MARKER")
        sudo /nix/var/nix/profiles/system-${stable_gen}-link/bin/switch-to-configuration switch 2>/dev/null || true
      fi
      rm -f "$TEST_MARKER"
      exit 1
    fi
    echo "=== 自动确认：测试 ${elapsed_days} 天无异常 ==="
    sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader
    new_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "$new_gen" > "$STABLE_MARKER"
    rm -f "$TEST_MARKER" "$CRASH_LOG"
    notify "测试通过！Generation $new_gen 已正式写入 GRUB"
    echo "✓ Generation $new_gen 已自动确认为稳定版"
    ;;
  confirm)
    if [ ! -f "$TEST_MARKER" ]; then echo "没有正在测试的配置。"; exit 1; fi
    echo "正式应用配置到 GRUB..."
    sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader
    new_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "$new_gen" > "$STABLE_MARKER"
    rm -f "$TEST_MARKER" "$CRASH_LOG"
    notify "手动确认！Generation $new_gen 已正式写入 GRUB"
    echo "✓ Generation $new_gen 是新的稳定版。"
    ;;
  rollback)
    if [ ! -f "$STABLE_MARKER" ]; then
      sudo nixos-rebuild switch --rollback; exit 0
    fi
    stable_gen=$(cat "$STABLE_MARKER")
    echo "回滚到稳定版 generation $stable_gen..."
    sudo /nix/var/nix/profiles/system-${stable_gen}-link/bin/switch-to-configuration switch
    rm -f "$TEST_MARKER" "$CRASH_LOG"
    notify "已手动回滚到 Generation $stable_gen" "critical"
    echo "✓ 已回滚到 generation $stable_gen"
    ;;
  status)
    current_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "=== NixOS 智能安全升级状态 ==="
    echo "当前 generation: $current_gen"
    if [ -f "$STABLE_MARKER" ]; then
      echo "稳定版 generation: $(cat "$STABLE_MARKER")"
    else
      echo "稳定版: 未记录（当前即稳定版）"
    fi
    if [ -f "$TEST_MARKER" ]; then
      test_start=$(cat "$TEST_MARKER")
      now=$(date +%s)
      elapsed_days=$(( (now - test_start) / 86400 ))
      elapsed_hours=$(( (now - test_start) / 3600 ))
      remaining=$(( CONFIRM_DAYS - elapsed_days ))
      echo "测试状态: 运行中 ($elapsed_hours 小时 / $elapsed_days 天)"
      [ "$remaining" -gt 0 ] && echo "自动确认: 还需 $remaining 天" || echo ">>> 等待下次自动确认检查"
      check_health "$test_start" 2>/dev/null && echo "系统健康: ✓ 正常" || echo "系统健康: ✗ 有异常"
    else
      echo "测试状态: 无"
    fi
    [ -f "$STATE_DIR/history.log" ] && { echo ""; echo "--- 最近记录 ---"; tail -5 "$STATE_DIR/history.log"; }
    ;;
  *) echo "用法: $0 {test|auto-confirm|confirm|rollback|status}"; exit 1 ;;
esac
