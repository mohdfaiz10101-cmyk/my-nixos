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

  # 1a. 基础设施层：LiteLLM（ChromaDB/Letta 等已迁移或移除）
  systemd.services.ai-infrastructure = {
    description = "AI Infrastructure (LiteLLM)";
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "300";
      ExecStart = pkgs.writeShellScript "ai-infra-start" ''
        for dir in /mnt/ai-cluster/litellm /mnt/ai/ai-cluster/litellm; do
          [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose up -d) || true
        done
      '';
      ExecStop = pkgs.writeShellScript "ai-infra-stop" ''
        for dir in /mnt/ai-cluster/litellm /mnt/ai/ai-cluster/litellm; do
          [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose down) || true
        done
      '';
    };
  };

  # 1b. Letta Agent 框架（按需启动，目录不存在则跳过）
  systemd.services.letta-compose = {
    description = "Letta Agent Framework (Docker)";
    after = [ "docker.service" "ai-infrastructure.service" ];
    wants = [ "ai-infrastructure.service" ];
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "180";
      ExecStart = pkgs.writeShellScript "letta-start" ''
        for dir in /mnt/ai-cluster/letta /mnt/ai/ai-cluster/letta; do
          [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose up -d) || true
        done
      '';
      ExecStop = pkgs.writeShellScript "letta-stop" ''
        for dir in /mnt/ai-cluster/letta /mnt/ai/ai-cluster/letta; do
          [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose down) || true
        done
      '';
    };
  };

  # 1c. 应用平台层（按需启动，目录不存在则跳过）
  systemd.services.ai-apps = {
    description = "AI Apps (auto-discover compose projects)";
    after = [ "docker.service" "letta-compose.service" ];
    wants = [ "letta-compose.service" ];
    path = with pkgs; [ docker docker-compose coreutils bash ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "600";
      ExecStart = pkgs.writeShellScript "ai-apps-start" ''
        for CLUSTER in /mnt/ai-cluster /mnt/ai/ai-cluster; do
          for dir in "$CLUSTER"/*/; do
            name=$(basename "$dir")
            case "$name" in litellm|letta) continue ;; esac
            [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose up -d) || true
          done
          [ -f "$CLUSTER/dify/docker/docker-compose.yaml" ] && \
            (cd "$CLUSTER/dify/docker" && docker compose up -d) || true
        done
      '';
      ExecStop = pkgs.writeShellScript "ai-apps-stop" ''
        for CLUSTER in /mnt/ai-cluster /mnt/ai/ai-cluster; do
          for dir in "$CLUSTER"/*/; do
            name=$(basename "$dir")
            case "$name" in litellm|letta) continue ;; esac
            [ -f "$dir/docker-compose.yml" ] && (cd "$dir" && docker compose down) || true
          done
        done
      '';
    };
  };

  # 2. 微信增量同步（已禁用 — 目录不存在）
  # 如需恢复：创建 /mnt/ai-cluster/wechat-sync/sync.py 后取消注释
  # systemd.services.wechat-sync = {
  #   description = "WeChat incremental sync";
  #   path = with pkgs; [ python3 sqlite bash coreutils procps sqlcipher ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     User = "charlie";
  #     WorkingDirectory = "/mnt/ai-cluster/wechat-sync";
  #     ExecStart = "${pkgs.bash}/bin/bash -c 'test -f sync.py && python3 sync.py || true'";
  #   };
  # };
  # systemd.timers.wechat-sync = {
  #   description = "WeChat sync every 15 minutes";
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnBootSec = "5min";
  #     OnUnitActiveSec = "15min";
  #     Persistent = true;
  #   };
  # };

  # 3. 知识蒸馏（已禁用 — 目录不存在）
  # systemd.services.knowledge-distill = { ... };
  # systemd.timers.knowledge-distill = { ... };

  # 4. 健康监控 + Telegram 报警（每5分钟）
  systemd.services.health-monitor = {
    description = "System health monitor with Telegram alerts";
    path = with pkgs; [ docker curl bash coreutils gawk hostname ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30";
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
      TimeoutStartSec = "60";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/nixos-safe-upgrade.sh auto-confirm";
    };
  };

  # nixos-auto-confirm timer DISABLED — 会触发 switch 导致 NVIDIA D-state 死锁
  # 如需手动升级: sudo bash /etc/nixos/scripts/nixos-safe-upgrade.sh test
  systemd.timers.nixos-auto-confirm = {
    description = "Daily check: auto-confirm NixOS test config after 3 days (15:00)";
    wantedBy = [];  # 禁用自动启动
    timerConfig = {
      OnBootSec = "10min";
      OnCalendar = "*-*-* 15:00:00";
      Persistent = true;
    };
  };

  # 6. 统一搜索系统（已禁用 — 目录不存在）
  # 如需恢复：将代码放到 /mnt/ai-cluster/unified-search/ 后取消注释
  # systemd.services.unified-search = { ... };

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
      TimeoutStartSec = "900";
      ExecStart = pkgs.writeShellScript "ai-docker-delayed-start" ''
        echo "Starting AI infrastructure services..."
        systemctl start ai-infrastructure.service || true
        systemctl start letta-compose.service || true
        systemctl start ai-apps.service || true
        echo "AI services started."
      '';
    };
  };

  # 8. fwupd-refresh 超时保护（原 infinity → 120s）
  systemd.services.fwupd-refresh.serviceConfig.TimeoutStartSec = lib.mkForce "120";

  # 9. 开机自动恢复服务（5 分钟后运行，修复失败服务、Docker 容器、磁盘）
  systemd.services.boot-recovery = {
    description = "Boot Auto-Recovery — fix failed services and notify Telegram";
    after = [ "network-online.target" "docker.service" "multi-user.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ bash curl docker systemd coreutils nix sudo python3 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      TimeoutStartSec = "300";
      ExecStart = "/home/charlie/.local/bin/boot-recovery.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.boot-recovery = {
    description = "Trigger boot-recovery 5 minutes after boot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      Unit = "boot-recovery.service";
    };
  };

  # 10. 每日系统日报 → 固定 OpenCode session
  systemd.services.daily-report = {
    description = "Daily system report to OpenCode session";
    path = with pkgs; [ python3 systemd docker docker-client coreutils ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30";
      ExecStart = "${pkgs.python3}/bin/python3 /home/charlie/agi/daily-report.py";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.daily-report = {
    description = "Daily system report at 09:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 09:00:00";
      Persistent = true;
    };
  };

  # Hyprland 冻屏 watchdog — hyprctl 超时 5s → SysRq 重启
  systemd.services.hyprland-freeze-watchdog = {
    description = "Hyprland freeze detector";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "hyprland-freeze-watch" ''
        HYPR_PID=$(pgrep -x Hyprland 2>/dev/null)
        [ -z "$HYPR_PID" ] && exit 0
        if ! timeout 5 runuser -l charlie -c 'hyprctl monitors > /dev/null 2>&1'; then
          echo "Hyprland frozen, rebooting" | systemd-cat -p crit -t hyprland-watchdog
          echo 1 > /proc/sys/kernel/sysrq
          sync
          echo b > /proc/sysrq-trigger
        fi
      '';
    };
  };
  systemd.timers.hyprland-freeze-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "30s"; AccuracySec = "5s"; };
  };


  # ===== 智能 Nix GC：保留当前 + stable标记 + 最近3个，删其余 =====
  systemd.services.smart-nix-gc = {
    description = "Smart Nix GC - keep current, stable, last 3 gens";
    path = with pkgs; [ nix coreutils gnugrep gawk ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "smart-nix-gc" ''
        PROFILE=/nix/var/nix/profiles/system
        STABLE_FILE=/var/lib/nixos-safe-upgrade/stable-generation
        CURRENT=$(readlink "$PROFILE" | grep -oP 'system-\K[0-9]+(?=-link)' || echo 0)
        STABLE=$(cat "$STABLE_FILE" 2>/dev/null || echo "")
        echo "Current:$CURRENT Stable:$STABLE"
        ALL=$(nix-env --profile "$PROFILE" --list-generations | awk '{print $1}')
        RECENT=$(echo "$ALL" | tail -3)
        for gen in $ALL; do
          skip=0
          [ "$gen" = "$CURRENT" ] && skip=1
          [ -n "$STABLE" ] && [ "$gen" = "$STABLE" ] && skip=1
          echo "$RECENT" | grep -qx "$gen" && skip=1
          [ "$skip" = 0 ] && nix-env --profile "$PROFILE" --delete-generations "$gen"
        done
        nix-collect-garbage
        nix-store --optimise 2>/dev/null || true
        echo "GC done. Free: $(df -h / | tail -1 | awk '{print $4}')"
      '';
    };
  };
  systemd.timers.smart-nix-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "Sun 03:00"; Persistent = true; };
  };


  # ===== 自动稳定性检测：48h 无问题 → 自动升为 stable gen =====
  systemd.services.auto-stable-detect = {
    description = "Auto stable generation detector";
    path = with pkgs; [ coreutils gnugrep gawk procps libnotify systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/etc/nixos/scripts/auto-stable-detect.sh";
      StandardOutput = "journal";
    };
  };
  systemd.timers.auto-stable-detect = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";   # 每小时检查一次
      Persistent = false;
    };
  };

}
