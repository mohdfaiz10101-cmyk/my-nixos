{ config, pkgs, lib, ... }:

# ============================================================
# 自动化服务模块
#
# 修复的缺陷：
#   1. Docker 服务不自动启动 → 开机自动拉起所有 compose 项目
#   2. 微信没定时同步 → 每15分钟增量同步
#   3. 知识蒸馏没自动化 → 每6小时蒸馏新对话
#   4. 健康监控缺失 → 每5分钟检查+Telegram报警
#   6. 统一搜索系统 → 端口 9000
# ============================================================

{
  # 1. Docker AI 集群开机自启
  systemd.services.ai-cluster = {
    description = "Start AI Docker Compose services";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/ai-cluster-start.sh";
      ExecStop = "${pkgs.bash}/bin/bash /etc/nixos/scripts/ai-cluster-stop.sh";
      TimeoutStartSec = "600";
    };
  };

  # 2. 微信增量同步（每15分钟）
  systemd.services.wechat-sync = {
    description = "WeChat incremental sync";
    path = with pkgs; [ python3 sqlite bash coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "charlie";
      WorkingDirectory = "/mnt/ai/ai-cluster/wechat-sync";
      ExecStart = "${pkgs.bash}/bin/bash -c 'test -f sync.py && python3 sync.py || true'";
    };
  };

  systemd.timers.wechat-sync = {
    description = "WeChat sync every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };

  # 3. 知识蒸馏（每6小时）
  systemd.services.knowledge-distill = {
    description = "Knowledge distillation from conversations";
    path = with pkgs; [ docker docker-compose bash coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'cd /mnt/ai/ai-cluster/knowledge-distiller && docker compose run --rm distiller 2>/dev/null || true'";
      TimeoutStartSec = "1800";
    };
  };

  systemd.timers.knowledge-distill = {
    description = "Periodic knowledge distillation";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };

  # 4. 健康监控 + Telegram 报警（每5分钟）
  systemd.services.health-monitor = {
    description = "System health monitor with Telegram alerts";
    path = with pkgs; [ docker curl bash coreutils gawk ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/health-monitor.sh";
    };
  };

  systemd.timers.health-monitor = {
    description = "Periodic health check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };

  # 5. NixOS 智能安全升级：自动确认 timer
  systemd.services.nixos-auto-confirm = {
    description = "NixOS auto-confirm tested configuration";
    path = with pkgs; [ bash coreutils systemd nix nixos-rebuild libnotify sudo ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/nixos-safe-upgrade.sh auto-confirm";
    };
  };

  systemd.timers.nixos-auto-confirm = {
    description = "Daily check: auto-confirm NixOS test config after 3 days";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # 6. 统一搜索系统 (端口 9000)
  systemd.services.unified-search = let
    pythonEnv = pkgs.python313.withPackages (ps: with ps; [
      fastapi uvicorn httpx
      pypdf python-docx openpyxl  # 文档解析: PDF/Word/Excel
    ]);
  in {
    description = "Unified Search Gateway (port 9000)";
    after = [ "network.target" "docker.service" "ai-cluster.service" "ollama.service" ];
    wants = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "charlie";
      WorkingDirectory = "/mnt/ai/ai-cluster/unified-search";
      ExecStart = "${pythonEnv}/bin/python3 /mnt/ai/ai-cluster/unified-search/app.py";
      Restart = "on-failure";
      RestartSec = "10s";
      Environment = "HOME=/home/charlie";
    };
  };
}
