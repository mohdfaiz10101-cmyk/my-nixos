#!/usr/bin/env bash
# recover-from-git.sh — 從 Git 遠端拉取配置並重建系統
# 用法：nix-recover（開機進 Gen 64 後執行）
set -euo pipefail

NIXOS_DIR="/etc/nixos"
FLAKE="$NIXOS_DIR#charlie"
PROXY="http://127.0.0.1:7890"

echo "=== NixOS 遠端恢復腳本 ==="
echo ""

# --- 1. 測試網路連通性 ---
echo "[1/4] 測試網路..."
if curl -s -m 5 -o /dev/null https://github.com 2>/dev/null; then
  echo "  直連 GitHub OK"
elif curl -s -m 5 -o /dev/null --proxy "$PROXY" https://github.com 2>/dev/null; then
  echo "  直連失敗，走代理 $PROXY"
  export http_proxy="$PROXY"
  export https_proxy="$PROXY"
  export HTTP_PROXY="$PROXY"
  export HTTPS_PROXY="$PROXY"
else
  echo "  錯誤：無法連接 GitHub（直連和代理都失敗）"
  echo "  請先確認網路連線，或手動設定代理："
  echo "    export https_proxy=http://127.0.0.1:7890"
  exit 1
fi

# --- 2. 備份本地配置 ---
echo ""
echo "[2/4] 備份本地配置..."
BACKUP_DIR="/tmp/nixos-backup-$(date +%Y%m%d-%H%M%S)"
cp -r "$NIXOS_DIR" "$BACKUP_DIR" 2>/dev/null || true
echo "  備份到 $BACKUP_DIR"

# --- 3. Git pull ---
echo ""
echo "[3/4] 從遠端拉取最新配置..."
cd "$NIXOS_DIR"

# 顯示當前狀態
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "  當前分支: $CURRENT_BRANCH"

# stash 本地改動（避免衝突）
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "  本地有未提交改動，先 stash..."
  git stash push -m "recover-backup-$(date +%Y%m%d-%H%M%S)"
fi

# pull
if git pull origin "$CURRENT_BRANCH" 2>&1; then
  echo "  Git pull 成功"
else
  echo "  Git pull 失敗，嘗試 reset 到遠端版本..."
  read -p "  確認要丟棄本地改動，強制同步遠端？(y/N) " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    git fetch origin
    git reset --hard "origin/$CURRENT_BRANCH"
    echo "  已同步到遠端版本"
  else
    echo "  取消操作"
    exit 1
  fi
fi

# --- 4. 重建系統 ---
echo ""
echo "[4/4] 重建系統..."
echo "  先 build 驗證..."
if nixos-rebuild build --flake "$FLAKE"; then
  echo "  Build 成功，切換系統..."
  nixos-rebuild switch --flake "$FLAKE" --install-bootloader
  echo ""
  echo "=== 恢復完成！==="
  echo "系統已切換到遠端最新配置。"
else
  echo ""
  echo "  Build 失敗！本地備份在: $BACKUP_DIR"
  echo "  可以手動恢復: cp -r $BACKUP_DIR/* $NIXOS_DIR/"
  exit 1
fi
