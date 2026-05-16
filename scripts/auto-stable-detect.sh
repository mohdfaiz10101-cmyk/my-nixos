#!/usr/bin/env bash
# 自动稳定性检测：boot 后持续观察，判断当前 gen 是否稳定
set -euo pipefail

STATE_DIR=/var/lib/nixos-safe-upgrade
STABLE_FILE="$STATE_DIR/stable-generation"
BOOT_TIME_FILE="$STATE_DIR/boot-time"
OBSERVE_HOURS=48   # 观察 48 小时

mkdir -p "$STATE_DIR"

PROFILE=/nix/var/nix/profiles/system
CURRENT_GEN=$(readlink "$PROFILE" | grep -oP 'system-\K\d+(?=-link)' || echo 0)
CURRENT_SYS=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep INIT_PATH || readlink /run/current-system)

# 记录启动时间（首次运行）
if [ ! -f "$BOOT_TIME_FILE" ]; then
  date +%s > "$BOOT_TIME_FILE"
  echo "$CURRENT_GEN" > "$STATE_DIR/testing-generation"
  echo "[auto-stable] Gen $CURRENT_GEN 进入 testing 观察期 (48h)"
  exit 0
fi

TESTING_GEN=$(cat "$STATE_DIR/testing-generation" 2>/dev/null || echo 0)

# 如果 gen 变了（重启换了 gen），重置计时
if [ "$CURRENT_GEN" != "$TESTING_GEN" ]; then
  date +%s > "$BOOT_TIME_FILE"
  echo "$CURRENT_GEN" > "$STATE_DIR/testing-generation"
  echo "[auto-stable] Gen 切换: $TESTING_GEN → $CURRENT_GEN，重新计时"
  exit 0
fi

# 检查观察时间
BOOT_TIME=$(cat "$BOOT_TIME_FILE")
NOW=$(date +%s)
ELAPSED_H=$(( (NOW - BOOT_TIME) / 3600 ))

# 稳定性评分
issues=0

# 检查 D 态进程堆积（过去 1 小时）
d_count=$(grep -l 'State:.*D' /proc/[0-9]*/status 2>/dev/null | wc -l)
[ "$d_count" -gt 15 ] && issues=$((issues+1)) && echo "[auto-stable] ❌ D态进程: $d_count"

# 检查 OOM（过去 24h）
oom=$(journalctl -k --since "24h ago" --no-pager -q 2>/dev/null | grep -c 'Out of memory' || true)
[ "$oom" -gt 0 ] && issues=$((issues+1)) && echo "[auto-stable] ❌ OOM 事件: $oom 次"

# 检查 Hyprland 崩溃次数（过去 24h）
hypr_crashes=$(journalctl --since "24h ago" --no-pager -q 2>/dev/null | grep -c 'Hyprland.*crash\|signal 11\|Segmentation' || true)
[ "$hypr_crashes" -gt 2 ] && issues=$((issues+1)) && echo "[auto-stable] ❌ Hyprland 崩溃: $hypr_crashes 次"

# 已经达到观察时间且无问题 → 标记为 stable
if [ "$ELAPSED_H" -ge "$OBSERVE_HOURS" ] && [ "$issues" -eq 0 ]; then
  OLD_STABLE=$(cat "$STABLE_FILE" 2>/dev/null || echo "none")
  echo "$CURRENT_GEN" > "$STABLE_FILE"
  rm -f "$BOOT_TIME_FILE"
  echo "[auto-stable] ✅ Gen $CURRENT_GEN 自动升为 stable (观察 ${ELAPSED_H}h，${issues} 问题)"
  # 桌面通知
  DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"     notify-send -u normal "NixOS" "Gen $CURRENT_GEN 已自动标记为稳定版 ✅" 2>/dev/null || true
else
  echo "[auto-stable] Gen $CURRENT_GEN 观察中: ${ELAPSED_H}h/${OBSERVE_HOURS}h，问题: $issues"
fi
