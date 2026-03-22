#!/usr/bin/env bash
# NixOS 安全升级系统：test → 3天观察 → switch
# 用法:
#   nixos-test          — 测试新配置（重启自动回滚）
#   nixos-confirm       — 3天后确认，正式应用
#   nixos-rollback      — 手动回滚到稳定版
#   nixos-status        — 查看当前状态
set -euo pipefail

STABLE_MARKER="/var/lib/nixos-safe-upgrade/stable-generation"
TEST_MARKER="/var/lib/nixos-safe-upgrade/test-started"
CONFIRM_DAYS=3
STATE_DIR="/var/lib/nixos-safe-upgrade"

mkdir -p "$STATE_DIR"

cmd="${1:-status}"

case "$cmd" in
  test)
    # 记录当前稳定版 generation
    current_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "$current_gen" > "$STABLE_MARKER"
    date +%s > "$TEST_MARKER"

    echo "=== 安全测试模式 ==="
    echo "当前稳定版: generation $current_gen（已记录）"
    echo "正在编译并激活测试配置..."

    # test 模式：激活但不写 GRUB
    sudo nixos-rebuild test --flake /etc/nixos#charlie

    echo ""
    echo "✓ 测试配置已激活！"
    echo "  - 重启 = 自动回到 generation $current_gen（稳定版）"
    echo "  - 满意后运行: nixos-confirm"
    echo "  - 手动回滚: nixos-rollback"
    echo "  - $CONFIRM_DAYS 天后未确认 = 下次重启自动回滚"
    ;;

  confirm)
    if [ ! -f "$TEST_MARKER" ]; then
      echo "没有正在测试的配置。"
      exit 1
    fi

    test_start=$(cat "$TEST_MARKER")
    now=$(date +%s)
    elapsed_days=$(( (now - test_start) / 86400 ))

    echo "测试已运行 $elapsed_days 天。"

    if [ "$elapsed_days" -lt "$CONFIRM_DAYS" ]; then
      read -p "还不到 ${CONFIRM_DAYS} 天，确定要提前应用吗？[y/N] " -r
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消。继续测试。"
        exit 0
      fi
    fi

    echo "正式应用配置到 GRUB..."
    sudo nixos-rebuild switch --flake /etc/nixos#charlie

    # 更新稳定版记录
    new_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "$new_gen" > "$STABLE_MARKER"
    rm -f "$TEST_MARKER"

    # git: merge testing → stable（如果用分支管理）
    cd /etc/nixos
    if git rev-parse --verify stable >/dev/null 2>&1; then
      current_branch=$(git branch --show-current)
      git checkout stable
      git merge "$current_branch" -m "confirm: 测试通过，合并到 stable"
      git checkout "$current_branch"
      echo "✓ Git stable 分支已更新"
    fi

    echo ""
    echo "✓ 配置已正式应用！generation $new_gen 是新的稳定版。"
    ;;

  rollback)
    if [ ! -f "$STABLE_MARKER" ]; then
      echo "没有记录稳定版。使用 nixos-rebuild switch --rollback"
      sudo nixos-rebuild switch --rollback
      exit 0
    fi

    stable_gen=$(cat "$STABLE_MARKER")
    echo "回滚到稳定版 generation $stable_gen..."

    # 切换回稳定版
    sudo /nix/var/nix/profiles/system-${stable_gen}-link/bin/switch-to-configuration switch
    rm -f "$TEST_MARKER"

    echo "✓ 已回滚到 generation $stable_gen"
    ;;

  status)
    current_gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
    echo "=== NixOS 安全升级状态 ==="
    echo "当前 generation: $current_gen"

    if [ -f "$STABLE_MARKER" ]; then
      stable_gen=$(cat "$STABLE_MARKER")
      echo "稳定版 generation: $stable_gen"
    else
      echo "稳定版: 未记录（当前即稳定版）"
    fi

    if [ -f "$TEST_MARKER" ]; then
      test_start=$(cat "$TEST_MARKER")
      now=$(date +%s)
      elapsed_days=$(( (now - test_start) / 86400 ))
      elapsed_hours=$(( (now - test_start) / 3600 ))
      echo "测试状态: 运行中 ($elapsed_hours 小时 / $elapsed_days 天)"
      remaining=$(( CONFIRM_DAYS - elapsed_days ))
      if [ "$remaining" -gt 0 ]; then
        echo "建议再测试 $remaining 天后确认"
      else
        echo ">>> 已超过 ${CONFIRM_DAYS} 天，可以运行 nixos-confirm 正式应用！"
      fi
    else
      echo "测试状态: 无"
    fi
    ;;

  *)
    echo "用法: $0 {test|confirm|rollback|status}"
    exit 1
    ;;
esac
