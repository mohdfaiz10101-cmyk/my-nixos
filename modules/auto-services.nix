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
#
# 启动优化（SPE-31）：
#   AI Docker 服务改为延迟启动，不阻塞 multi-user.target/graphical.target
#   通过 ai-docker-delayed.timer 在开机 3 分钟后触发，桌面快速可用
# ============================================================

{
  # 1. Docker AI 集群 — 拆分为 3 个独立服务（可单独管理/重启）
  # ⚡ 注意：所有 AI Docker 服务已移除 wantedBy = ["multi-user.target"]
  #    改由 ai-docker-delayed.timer 延迟 3 分钟启动，加快桌面响应速度

  # 1a. 基础设施层：ChromaDB + LiteLLM
  systemd.services.ai-infrastructure = {
    description = "AI Infrastructure (ChromaDB + LiteLLM)";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    # 已移除: wantedBy = [ "multi-user.target" ]; → 改由 ai-docker-delayed 触发
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "300";
      ExecStart = pkgs.writeShellScript "ai-infra-start" ''
        CLUSTER="/mnt/ai/ai-cluster"
        for svc in chroma litellm; do
          [ -f "$CLUSTER/$svc/docker-compose.yml" ] && \
            (cd "$CLUSTER/$svc" && docker compose up -d) || true
        done
      '';
      ExecStop = pkgs.writeShellScript "ai-infra-stop" ''
        CLUSTER="/mnt/ai/ai-cluster"
        for svc in chroma litellm; do
          [ -f "$CLUSTER/$svc/docker-compose.yml" ] && \
            (cd "$CLUSTER/$svc" && docker compose down) || true
        done
      '';
    };
  };

  # 1b. Letta Agent 框架
  systemd.services.letta-compose = {
    description = "Letta Agent Framework (Docker)";
    after = [ "docker.service" "ai-infrastructure.service" ];
    wants = [ "ai-infrastructure.service" ];
    # 已移除: wantedBy = [ "multi-user.target" ]; → 改由 ai-docker-delayed 触发
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "180";
      ExecStart = pkgs.writeShellScript "letta-start" ''
        CLUSTER="/mnt/ai/ai-cluster"
        [ -f "$CLUSTER/letta/docker-compose.yml" ] && \
          (cd "$CLUSTER/letta" && docker compose up -d) || true
      '';
      ExecStop = pkgs.writeShellScript "letta-stop" ''
        cd /mnt/ai/ai-cluster/letta && docker compose down || true
      '';
    };
  };

  # 1c. 应用平台层：Dify + n8n + Open WebUI + 其他
  systemd.services.ai-apps = {
    description = "AI Apps (Dify + n8n + Open WebUI + others)";
    after = [ "docker.service" "letta-compose.service" ];
    wants = [ "letta-compose.service" ];
    # 已移除: wantedBy = [ "multi-user.target" ]; → 改由 ai-docker-delayed 触发
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "600";
      ExecStart = pkgs.writeShellScript "ai-apps-start" ''
        CLUSTER="/mnt/ai/ai-cluster"
        for svc in hyper-os n8n open-webui; do
          [ -f "$CLUSTER/$svc/docker-compose.yml" ] && \
            (cd "$CLUSTER/$svc" && docker compose up -d) || true
        done
        [ -f "$CLUSTER/dify/docker/docker-compose.yaml" ] && \
          (cd "$CLUSTER/dify/docker" && docker compose up -d) || true
        for svc in autogen guacamole-local erpnext trip-map; do
          [ -f "$CLUSTER/$svc/docker-compose.yml" ] && \
            (cd "$CLUSTER/$svc" && docker compose up -d) || true
        done
      '';
      ExecStop = pkgs.writeShellScript "ai-apps-stop" ''
        CLUSTER="/mnt/ai/ai-cluster"
        for dir in "$CLUSTER"/*/; do
          name=$(basename "$dir")
          case "$name" in chroma|litellm|letta) continue ;; esac
          [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose down) || true
        done
        [ -f "$CLUSTER/dify/docker/docker-compose.yaml" ] && \
          (cd "$CLUSTER/dify/docker" && docker compose down) || true
      '';
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
    # 依赖 ai-infrastructure（docker compose），不阻塞 multi-user.target
    after = [ "network.target" "docker.service" "ai-infrastructure.service" "ollama.service" ];
    wants = [ "ollama.service" ];
    # 已移除: wantedBy = [ "multi-user.target" ]; → 改由 ai-docker-delayed 触发

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

  # 7. ⚡ AI 服务延迟启动调度器（SPE-31 启动优化）
  # 开机 3 分钟后触发所有 AI Docker 服务，不阻塞桌面登录
  systemd.timers.ai-docker-delayed = {
    description = "Delayed start of AI Docker services after boot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";    # 桌面就绪后 3 分钟启动，确保桌面流畅
      Unit = "ai-docker-delayed.service";
    };
  };

  systemd.services.ai-docker-delayed = {
    description = "Start AI Docker services (delayed after boot)";
    after = [ "docker.service" "network-online.target" "mnt-ai.mount" ];
    wants = [ "docker.service" "network-online.target" ];
    path = with pkgs; [ systemd bash coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "ai-docker-delayed-start" ''
        echo "Starting AI infrastructure services..."
        systemctl start ai-infrastructure.service || true
        systemctl start letta-compose.service || true
        systemctl start ai-apps.service || true
        systemctl start unified-search.service || true
        echo "AI services started."
      '';
    };
  };
}
