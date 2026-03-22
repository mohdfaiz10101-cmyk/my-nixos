#!/usr/bin/env bash
# Claude 配置自动同步脚本
# 将 root 的 Claude 登录凭证同步到 charlie 用户

set -euo pipefail

ROOT_CLAUDE="/root/.claude"
CHARLIE_CLAUDE="/home/charlie/.claude"

# 确保 charlie 目录存在
mkdir -p "$CHARLIE_CLAUDE"

# 同步凭证和设置（只复制已存在的文件）
for file in .credentials.json settings.json settings.local.json; do
    if [ -f "$ROOT_CLAUDE/$file" ]; then
        cp "$ROOT_CLAUDE/$file" "$CHARLIE_CLAUDE/$file"
    fi
done

# 修正权限
chown -R charlie:users "$CHARLIE_CLAUDE"
chmod 700 "$CHARLIE_CLAUDE"
chmod 600 "$CHARLIE_CLAUDE"/.credentials.json 2>/dev/null || true

echo "Claude 配置已同步到 charlie 用户"
