#!/usr/bin/env bash
# OpenCode Recovery Mode — 自动拉起 opencode 进行 AI 诊断修复
set -euo pipefail

# 等待网络
echo "[Recovery] 等待网络就绪..." > /dev/tty1
for i in $(seq 1 30); do
  if ping -c 1 -W 1 1.1.1.1 &>/dev/null; then
    echo "[Recovery] 网络就绪" > /dev/tty1
    break
  fi
  sleep 1
done

# 设置 PATH
export PATH="/home/charlie/.npm-global/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/home/charlie/.nix-profile/bin:$PATH"
export HOME="/home/charlie"

# 显示诊断信息
echo "" > /dev/tty1
echo "============================================" > /dev/tty1
echo "  🚑 NixOS OpenCode Recovery Mode" > /dev/tty1
echo "============================================" > /dev/tty1
echo "" > /dev/tty1
echo "系统信息:" > /dev/tty1
uname -a > /dev/tty1
echo "" > /dev/tty1
echo "检查失败服务:" > /dev/tty1
systemctl --failed --no-legend 2>/dev/null | head -10 > /dev/tty1
echo "" > /dev/tty1
echo "最近启动日志 (最后20行):" > /dev/tty1
journalctl -b -p err --no-pager -n 20 2>/dev/null > /dev/tty1
echo "" > /dev/tty1
echo "============================================" > /dev/tty1
echo "  正在启动 opencode AI 诊断..." > /dev/tty1
echo "  提示: 按 Ctrl+C 跳过，进入普通 shell" > /dev/tty1
echo "============================================" > /dev/tty1
echo "" > /dev/tty1

# 拉起 opencode（带超时，防止无限卡住）
cd /home/charlie
timeout 7200 opencode --model glm "你是 NixOS 系统急救 AI。当前系统从 OpenCode Recovery Mode 启动。请执行：
1. 运行 systemctl --failed 检查失败服务
2. 运行 journalctl -b -p err -n 30 查看启动错误
3. 分析根因并给出修复方案
4. 如需修复，给出具体 nix 配置修改命令" 2>&1 | tee /tmp/opencode-recovery.log

echo "" > /dev/tty1
echo "============================================" > /dev/tty1
echo "  opencode 已退出。你可以手动修复系统。" > /dev/tty1
echo "  修复后运行: sudo nixos-rebuild switch" > /dev/tty1
echo "  重启: sudo reboot" > /dev/tty1
echo "============================================" > /dev/tty1

# 启动 shell 让用户手动操作
exec /run/current-system/sw/bin/bash -l
