#!/usr/bin/env bash
# 固定一个稳定版 generation，永远不会被 GC 删除，永远在 GRUB 里
# 用法:
#   pin-stable          — 固定当前 generation 为稳定版
#   pin-stable restore  — 恢复被意外删除的 profile symlink
set -euo pipefail

PIN_FILE="/var/lib/nixos-safe-upgrade/pinned-stable"
GCROOT="/nix/var/nix/gcroots/pinned-stable-system"

cmd="${1:-pin}"

case "$cmd" in
  pin)
    current_gen_num=$(basename "$(readlink /nix/var/nix/profiles/system)" | grep -oP 'system-\K[0-9]+' || readlink /nix/var/nix/profiles/system | grep -oP '[0-9]+' || echo "unknown")
    current_profile=$(readlink -f /nix/var/nix/profiles/system)
    current_link="/nix/var/nix/profiles/system"

    # 1. 保护 store path（防止 nix-store --gc 删除）
    nix-store --add-root "$GCROOT" --indirect -r "$current_profile"

    # 2. 记录 generation 信息（用于恢复 profile symlink）
    cat > "$PIN_FILE" <<PINEOF
GENERATION_STORE_PATH=$current_profile
PINNED_DATE=$(date '+%Y-%m-%d %H:%M')
PINEOF

    echo "============================================"
    echo "  ✓ 稳定版已固定！"
    echo "  Store: $current_profile"
    echo "  GC root: $GCROOT"
    echo "  记录: $PIN_FILE"
    echo ""
    echo "  此版本永远不会被 GC 删除"
    echo "  如果 GRUB 启动项丢失，运行: pin-stable restore"
    echo "============================================"
    ;;

  restore)
    if [ ! -f "$PIN_FILE" ]; then
      echo "没有固定的稳定版。先运行: pin-stable"
      exit 1
    fi

    source "$PIN_FILE"

    # 检查 store path 是否还在
    if [ ! -d "$GENERATION_STORE_PATH" ]; then
      echo "错误：store path 已被删除！$GENERATION_STORE_PATH"
      echo "需要重新 rebuild：sudo nixos-rebuild switch --flake /etc/nixos#charlie"
      exit 1
    fi

    # 找到最大的 generation number
    max_gen=$(ls /nix/var/nix/profiles/system-*-link 2>/dev/null | grep -oP 'system-\K[0-9]+' | sort -n | tail -1)
    new_gen=$((max_gen + 1))

    # 重建 profile symlink
    ln -sfn "$GENERATION_STORE_PATH" "/nix/var/nix/profiles/system-${new_gen}-link"

    echo "✓ 已恢复稳定版为 generation $new_gen"
    echo "运行 nixos-rebuild boot 或重启即可在 GRUB 中看到"

    # 重新生成 GRUB
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot 2>/dev/null || true
    echo "✓ GRUB 已更新"
    ;;

  *)
    echo "用法: $0 {pin|restore}"
    ;;
esac
