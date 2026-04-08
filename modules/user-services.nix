{ config, pkgs, lib, ... }:

# ============================================================
# 用户 systemd 服务模块（聚合入口）
#
# 按功能域拆分到 services/ 子目录：
#   ai.nix    — AI 相关持久守护服务
#   web.nix   — Web / 终端持久服务
#   tools.nix — 工具类持久服务
#   timers.nix — 所有 oneshot 定时任务 + timer 定义
# ============================================================

{
  imports = [
    ./services/ai.nix
    ./services/web.nix
    ./services/tools.nix
    ./services/timers.nix
  ];
}
