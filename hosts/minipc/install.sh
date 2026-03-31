#!/usr/bin/env bash
# minipc 远程安装脚本（离线模式 — 在本机编译，推送到小主机）
# 用法：
#   1. 小主机用网线连到路由器（WiFi 在 LiveCD 可能不工作）
#   2. U 盘启动 NixOS LiveCD
#   3. 在 LiveCD 中设置 root 密码：sudo passwd root
#   4. 获取 IP：ip a（看 eth0/enp* 的地址）
#   5. 在本机运行此脚本：bash /etc/nixos/hosts/minipc/install.sh <小主机IP>
#
# 原理：nixos-anywhere --build-on local 在本机编译整个系统（本机有代理），
#       编译好后通过 SSH 推送到小主机，小主机不需要联网。

set -euo pipefail

IP="${1:?用法: $0 <小主机IP>}"

echo "========================================="
echo " nixos-anywhere → minipc (离线推送模式)"
echo " 目标: root@${IP}"
echo "========================================="
echo ""
echo "⚠  警告：目标机器的硬盘将被完全格式化！"
echo "   确保小主机已从 NixOS LiveCD 启动"
echo "   确保小主机用网线连接（WiFi 可能不工作）"
echo "   确保 root 密码已设置（sudo passwd root）"
echo ""
read -p "确认继续？(y/N) " confirm
[[ "$confirm" =~ ^[yY]$ ]] || exit 1

# 预检：SSH 连接测试
echo ""
echo ">>> 测试 SSH 连接..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"${IP}" echo "SSH OK" 2>/dev/null; then
  echo "❌ 无法连接 root@${IP}"
  echo "   请确认："
  echo "   - 小主机已从 LiveCD 启动"
  echo "   - 已执行 sudo passwd root"
  echo "   - 网线已连接，IP 正确"
  exit 1
fi

# 预检：探测小主机硬件
echo ""
echo ">>> 探测小主机硬件..."
echo "--- 磁盘 ---"
ssh -o StrictHostKeyChecking=no root@"${IP}" lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null || true
echo ""
echo "--- 网卡（WiFi） ---"
ssh -o StrictHostKeyChecking=no root@"${IP}" 'lspci 2>/dev/null | grep -i -E "network|wireless|wifi" || echo "无 PCI 无线网卡"' || true
ssh -o StrictHostKeyChecking=no root@"${IP}" 'lsusb 2>/dev/null | grep -i -E "wireless|wifi|wlan|802.11" || echo "无 USB 无线网卡"' || true
echo ""

# 检查磁盘设备
echo "提示：默认使用 /dev/sda"
echo "如果上面显示的是 nvme0n1，请先编辑 disk-config.nix 修改 device"
echo ""
read -p "磁盘设备正确？继续安装？(y/N) " confirm2
[[ "$confirm2" =~ ^[yY]$ ]] || exit 1

# 执行安装（离线模式：在本机编译，不要求目标机有网络）
echo ""
echo ">>> 开始安装（在本机编译，通过 SSH 推送）..."
echo "    编译可能需要较长时间，请耐心等待"
echo ""

HTTPS_PROXY=http://127.0.0.1:7890 \
nix run github:nix-community/nixos-anywhere -- \
  --build-on local \
  --flake /etc/nixos#minipc \
  root@"${IP}"

echo ""
echo "✅ 安装完成！小主机将自动重启"
echo "   重启后可通过以下方式连接："
echo "   ssh charlie@${IP}  （密码登录暂时关闭，需用 SSH 密钥）"
echo ""
echo "   首次登录后建议："
echo "   1. 设置密码：sudo passwd charlie"
echo "   2. 检查 WiFi：nmcli device wifi list"
echo "   3. 检查代理：proxy-status"
