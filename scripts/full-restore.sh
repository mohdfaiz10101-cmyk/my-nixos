#!/usr/bin/env bash
# 一键恢复脚本 — 重装系统后运行一次即可恢复全部
# 用法: sudo /etc/nixos/scripts/full-restore.sh
set -euo pipefail

echo "=== NixOS 全量恢复脚本 ==="
echo ""

# 1. 挂载数据盘
echo "[1/7] 挂载数据盘..."
mount -a 2>/dev/null || true
if mountpoint -q /mnt/data; then
  echo "  /mnt/data 已挂载"
else
  mount -t ntfs3 -o force,nofail,uid=1000 /dev/disk/by-uuid/C672D33272D32649 /mnt/data 2>/dev/null && echo "  /mnt/data 挂载成功" || echo "  警告: /mnt/data 挂载失败，数据盘可能未接"
fi
if mountpoint -q /mnt/ai; then
  echo "  /mnt/ai 已挂载"
else
  mount -o loop /mnt/data/ai-data.img /mnt/ai 2>/dev/null && echo "  /mnt/ai 挂载成功" || echo "  警告: /mnt/ai 挂载失败"
fi

# 2. 恢复 JetBrains 数据
echo "[2/7] 恢复 JetBrains 数据..."
if [ -d /mnt/data/config/JetBrains ]; then
  mkdir -p ~/.config/JetBrains ~/.cache/JetBrains
  cp -rn /mnt/data/config/JetBrains/* ~/.config/JetBrains/ 2>/dev/null && echo "  JetBrains 配置已恢复" || echo "  JetBrains 配置已是最新"
  cp -rn /mnt/data/cache/JetBrains/* ~/.cache/JetBrains/ 2>/dev/null || true
fi

# 3. 恢复用户数据备份
echo "[3/7] 恢复用户数据备份..."
if [ -d /mnt/data/home-backup ]; then
  for dir in .floorp .mozilla .config/Code .config/cursor .local/share/fcitx5; do
    if [ -d "/mnt/data/home-backup/$dir" ]; then
      mkdir -p "$HOME/$dir"
      cp -rn "/mnt/data/home-backup/$dir"/* "$HOME/$dir/" 2>/dev/null && echo "  已恢复 $dir" || true
    fi
  done
else
  echo "  未找到 home-backup，跳过"
fi

# 4. 安装 Flatpak 应用
echo "[4/7] 安装 Flatpak 应用..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
flatpak install -y --noninteractive flathub md.obsidian.Obsidian 2>/dev/null && echo "  Obsidian 已安装" || echo "  Obsidian 已存在或安装失败"

# 5. 拉取 Ollama 模型
echo "[5/7] 拉取 Ollama 模型..."
for model in qwen3:8b deepseek-r1:14b nomic-embed-text; do
  if ollama list 2>/dev/null | grep -q "$model"; then
    echo "  $model 已存在"
  else
    echo "  正在拉取 $model ..."
    ollama pull "$model" 2>/dev/null &
  fi
done
wait 2>/dev/null || true

# 6. 启动 Docker AI 集群
echo "[6/7] 启动 Docker AI 集群..."
if [ -d /mnt/ai/ai-cluster ]; then
  cd /mnt/ai/ai-cluster/dify/docker && docker compose up -d 2>/dev/null &
  cd /mnt/ai/ai-cluster/n8n && docker compose -p n8n2 up -d 2>/dev/null &
  cd /mnt/ai/ai-cluster/chroma && docker compose -p chroma2 up -d 2>/dev/null &
  cd /mnt/ai/ai-cluster/litellm && docker compose -p litellm up -d 2>/dev/null &
  cd /mnt/ai/ai-cluster/letta && docker compose -p letta up -d 2>/dev/null &
  echo "  Docker 服务正在后台启动..."
  wait 2>/dev/null || true
else
  echo "  未找到 AI 集群目录，跳过"
fi

# 7. GNOME 代理设置
echo "[7/7] 设置 GNOME 代理..."
gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null
gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null
gsettings set org.gnome.system.proxy.http port 7890 2>/dev/null
gsettings set org.gnome.system.proxy.http enabled true 2>/dev/null
gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null
gsettings set org.gnome.system.proxy.https port 7890 2>/dev/null
gsettings set org.gnome.system.proxy use-same-proxy false 2>/dev/null
gsettings set org.gnome.system.proxy.socks host '' 2>/dev/null
gsettings set org.gnome.system.proxy.socks port 0 2>/dev/null
echo "  GNOME 代理已设置"

echo ""
echo "=== 恢复完成！==="
echo "Docker 镜像可能还在后台拉取，用 'docker ps -a' 查看进度"
