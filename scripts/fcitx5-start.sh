#!/usr/bin/env bash
# fcitx5 自动启动脚本

# 等待图形环境就绪
sleep 2

# 设置环境变量
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export XDG_RUNTIME_DIR=/run/user/1000

# 停止可能存在的旧进程
pkill -9 fcitx5 2>/dev/null || true
sleep 1

# 启动 fcitx5
fcitx5 -d --replace &>/dev/null &

echo "fcitx5 已启动"
