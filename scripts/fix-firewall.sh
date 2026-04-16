#!/bin/bash
# Firewall 修复脚本
# 问题：自定义 firewall.service 与 NixOS 内置防火墙（nftables）冲突
# 解决：禁用自定义服务，使用 NixOS 内置防火墙

set -e

echo "[1/4] 禁用自定义 firewall.service"
sudo systemctl disable --now firewall

echo "[2/4] 删除自定义防火墙文件"
sudo rm /etc/systemd/system/firewall.service
sudo systemctl daemon-reload

echo "[3/4] 重新构建 NixOS 配置（应用内置防火墙）"
sudo nixos-rebuild switch --flake /etc/nixos#charlie

echo "[4/4] 验证防火墙规则"
sudo nft list ruleset

echo "✅ Firewall 修复完成"
echo "   - 自定义 firewall.service 已禁用"
echo "   - NixOS 内置防火墙已启用"
echo "   - 开放端口：22(SSH), 4000(LiteLLM), 8283/8284(Letta), 8000(Dify/n8n)"
