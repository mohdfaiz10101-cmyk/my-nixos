{ config, pkgs, lib, ... }:

# 所有 oneshot 定时任务服务 + timer 定义

let
  py = config.charlie.sharedPythonEnv;
  home = "/home/charlie";
  localBin = "${home}/.local/bin";
  launcher = "${home}/launcher";
  aiCluster = "/mnt/ai/ai-cluster";

  userEnv = {
    HOME = home;
    PYTHONUNBUFFERED = "1";
  };

  graphicalEnv = userEnv // {
    DISPLAY = ":0";
    WAYLAND_DISPLAY = "wayland-0";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
  };
in
{
  systemd.user.services = {

    # --- AI Scheduler ---
    ai-scheduler = {
      description = "AI Scheduler";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/ai-scheduler.sh";
      };
      path = [ pkgs.coreutils pkgs.bash ];
      environment = userEnv;
    };

    # --- Browser Cookie Sync ---
    # DISABLED: Floorp cookies.sqlite 不存在
    #     browser-cookie-sync = {
    #       description = "Browser Cookie Sync";
    #       serviceConfig = {
    #         Type = "oneshot";
    #         ExecStart = "${localBin}/sync-all-browser-cookies";
    #       };
    #     #     };

    # --- Claude Orphan Killer ---
    claude-orphan-killer = {
      description = "Kill orphaned Claude processes";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/claude-orphan-killer.sh";
      };
    };

    # --- GitHub AI Weekly ---
    github-ai-weekly = {
      description = "GitHub AI Weekly Trending Scanner";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/github-ai-weekly --notify";
      };
      environment = graphicalEnv;
    };

    # --- Health Check ---
    health-check = {
      description = "Weekly system health check";
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${launcher}/health-check.sh";
      };
      path = [ pkgs.coreutils pkgs.bash pkgs.curl ];
    };

    # --- Image Captioner ---
    image-captioner = {
      description = "Image Captioner (minicpm-v)";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = "${aiCluster}/unified-search";
        ExecStart = "${py}/bin/python3 image-captioner.py";
      };
      environment = userEnv;
    };

    # --- Letta Health Check ---
    letta-health-check = {
      description = "Letta Memory System Health Check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/test-letta-memory-system";
      };
    };

    # --- Letta Health Guard ---
    letta-health-guard = {
      description = "Letta Health Guard - 5-Layer Protection";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/letta-health-guard";
      };
      environment = { DOCKER_HOST = "unix:///var/run/docker.sock"; };
    };

    # --- Letta Health Monitor ---
    letta-health-monitor = {
      description = "Letta Memory Health Monitor with Auto-Fix";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/letta-health-monitor";
      };
    };

    # --- Letta Sync ---
    letta-sync = {
      description = "Sync Claude Code sessions to Letta";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/sync-session-to-letta";
      };
    };

    # --- Memory Backup ---
    memory-backup = {
      description = "Memory System Backup - Letta + ChromaDB + Files";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/memory-backup";
      };
    };

    # --- Memory Dream ---
    # DISABLED: 脚本未实现
    #     memory-dream = {
    #       description = "Memory Dream - AI memory consolidation";
    #       wants = [ "network-online.target" ];
    #       serviceConfig = {
    #         Type = "oneshot";
    #         ExecStart = "${localBin}/memory-dream";
    #       };
    #     #       environment = graphicalEnv;
    #     };

    # --- NixOS Auto Commit ---
    nixos-auto-commit = {
      description = "NixOS config auto-commit";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/nixos-auto-commit";
      };
    };

    # --- OCR Indexer ---
    ocr-indexer = {
      description = "OCR Image Text Indexer";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = "${aiCluster}/unified-search";
        ExecStart = "${py}/bin/python3 ocr-indexer.py";
        TimeoutStartSec = 600;
      };
      environment = userEnv;
      path = [
        pkgs.coreutils
        (pkgs.tesseract5.override { enableLanguages = [ "eng" "chi_sim" "chi_tra" ]; })
      ];
    };

    # --- System Health Monitor ---
    system-health-monitor = {
      description = "System Health Monitor";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/system-call-check";
      };
    };

    # --- Disk Cleanup ---
    disk-cleanup = {
      description = "Auto Disk Cleanup - JetBrains + Temp + Logs";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${launcher}/disk-cleanup.sh";
      };
      path = [ pkgs.coreutils pkgs.findutils pkgs.bash ];
    };

    # --- Disk Sentinel ---
    disk-sentinel = {
      description = "Disk Sentinel - Multi-threshold disk monitor";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${launcher}/disk-sentinel.sh";
      };
      path = [ pkgs.coreutils pkgs.findutils pkgs.bash pkgs.gawk pkgs.gnused pkgs.libnotify pkgs.nix ];
    };

    # --- Memory Sync to NTFS ---
    sync-memory-ntfs = {
      description = "Sync Claude memory to NTFS shared partition";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/sync-memory-to-ntfs";
      };
      environment = userEnv;
    };

    # --- Docker Prune ---
    docker-prune = {
      description = "Docker cleanup - remove unused images and containers";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.docker}/bin/docker system prune -a -f --volumes";
      };
      environment = { DOCKER_HOST = "unix:///var/run/docker.sock"; };
    };

    # --- Disk Space Monitor ---
    disk-space-monitor = {
      description = "Daily disk space monitor (alert at 80%)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'df -h --output=pcent,target | tail -n +2 | while read pct dir; do usage=$${pct%%%}; if [ $$usage -ge 80 ]; then echo \"WARNING: $$dir is at $$pct usage\"; fi; done'";
      };
    };

    # --- Maintenance Learner ---
    maintenance-learner = {
      description = "Smart Maintenance Learner - Scan memory patterns and generate suggestions";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${home}/.claude/skills/maintenance-learner.py --scan --json";
      };
      environment = userEnv;
    };

    # --- AI Architecture Audit ---
    ai-architecture-audit = {
      description = "AI Architecture Audit Dashboard - 7 dimensions health check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/ai-architecture-audit";
      };
      environment = graphicalEnv;
      path = [ pkgs.coreutils pkgs.bash pkgs.curl pkgs.jq pkgs.findutils pkgs.gnugrep ];
    };

    # --- Mihomo Backup ---
    mihomo-backup = {
      description = "Mihomo config incremental backup";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/mihomo-guardian --backup";
      };
      path = [ pkgs.coreutils pkgs.bash pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.diffutils ];
    };

    # --- Mihomo Guardian ---
    mihomo-guardian = {
      description = "Mihomo proxy health check with auto-rollback";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/mihomo-guardian --check";
        TimeoutStartSec = "120";
      };
      environment = graphicalEnv;
    };

    # --- Mihomo Watch ---
    mihomo-watch = {
      description = "Mihomo config file watcher (inotify)";
      wantedBy = [ "default.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/mihomo-guardian --watch";
        Restart = "on-failure";
        RestartSec = "30";
      };
      path = [ pkgs.inotify-tools ];
      environment = graphicalEnv;
    };

    # --- Backup Cleanup ---
    backup-cleanup = {
      description = "Monthly cleanup of .bak/.error/.save files in /etc/nixos/";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'find /etc/nixos/ \\( -name \"*.bak\" -o -name \"*.error\" -o -name \"*.save\" \\) -type f -delete -print 2>/dev/null || true'";
      };
    };

  };

  # ============================================================
  # Timers
  # ============================================================

  systemd.user.timers = {

    ai-scheduler = {
      description = "AI Scheduler timer (hourly)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
      };
    };

    #     browser-cookie-sync = {
    #       description = "Browser Cookie sync (every 5min)";
    #       wantedBy = [ "timers.target" ];
    #       timerConfig = {
    #         OnBootSec = "1min";
    #         OnUnitActiveSec = "5min";
    #       };
    #     };

    claude-orphan-killer = {
      description = "Claude orphan process killer (every 5min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        AccuracySec = "30";
      };
    };

    github-ai-weekly = {
      description = "Weekly GitHub AI Trending (Mon 09:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 09:00:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };

    health-check = {
      description = "Weekly health check (Mon 08:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 08:00:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    image-captioner = {
      description = "Image captioner (3x daily: 08:00/14:00/20:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 08,14,20:00:00";
        Persistent = true;
      };
    };

    letta-health-check = {
      description = "Letta health check (daily)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "12h";
        Persistent = true;
      };
    };

    letta-health-guard = {
      description = "Letta health guard (every 10min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    letta-health-monitor = {
      description = "Letta health monitor (every 6h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Persistent = true;
      };
    };

    letta-sync = {
      description = "Letta session sync (hourly)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    memory-backup = {
      description = "Memory backup (hourly)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    #     memory-dream = {
    #       description = "Memory dream consolidation (every 12h)";
    #       wantedBy = [ "timers.target" ];
    #       timerConfig = {
    #         OnBootSec = "10min";
    #         OnUnitActiveSec = "12h";
    #         Persistent = true;
    #       };
    #     };

    nixos-auto-commit = {
      description = "NixOS config auto-commit (daily 22:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 22:00:00";
        Persistent = true;
      };
    };

    ocr-indexer = {
      description = "OCR indexer (every 2h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "2h";
        Persistent = true;
      };
    };

    system-health-monitor = {
      description = "System health monitor (hourly)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    disk-cleanup = {
      description = "Auto disk cleanup (Sun 10:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 10:00:00";
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    disk-sentinel = {
      description = "Disk sentinel - check every 30min";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "30min";
        Persistent = true;
      };
    };

    sync-memory-ntfs = {
      description = "Sync memory to NTFS for Windows (every 2h + shutdown)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "2h";
        Persistent = true;
      };
    };

    docker-prune = {
      description = "Weekly Docker cleanup (Sun 10:30)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 10:30:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };

    disk-space-monitor = {
      description = "Disk space monitor (every 6h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "6h";
        OnBootSec = "10min";
        Persistent = true;
      };
    };

    backup-cleanup = {
      description = "Monthly cleanup of .bak/.error/.save files in /etc/nixos/ (1st 10:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-01 10:00:00";
        Persistent = true;
      };
    };

    # --- Maintenance Learner Timer ---
    maintenance-learner = {
      description = "Maintenance Learner weekly scan (Mon 11:00)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 11:00:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    mihomo-backup = {
      description = "Mihomo config backup (every 6h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Persistent = true;
      };
    };

    mihomo-guardian = {
      description = "Mihomo health check (every 10min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    # --- AI Architecture Audit Timer ---
    ai-architecture-audit = {
      description = "AI Architecture Audit weekly scan (Mon 09:30)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 09:30:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
