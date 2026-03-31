{ config, pkgs, lib, ... }:

# ============================================================
# 用户 systemd 服务模块
#
# 迁移 ~/.config/systemd/user/ 下的手工服务到 NixOS 声明式管理
# 分组：AI 服务 | Web 服务 | 工具服务 | 定时任务
# 排除：fcitx5（系统管理）、sunshine（系统管理）、disk-pool（独立模块）
# ============================================================

let
  py = config.charlie.sharedPythonEnv;
  home = "/home/charlie";
  localBin = "${home}/.local/bin";
  launcher = "${home}/launcher";
  aiCluster = "/mnt/ai/ai-cluster";

  # 通用环境变量
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
  # ============================================================
  # 一、AI / Claude 持久守护进程
  # ============================================================

  systemd.user.services = {

    # --- Agent 调度器 ---
    agent-orchestrator = {
      description = "Opus + GLM Agent Orchestrator";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${py}/bin/python3 ${home}/.local/lib/agent-orchestrator/orchestrator.py";
        WorkingDirectory = "${home}/.local/lib/agent-orchestrator";
        Restart = "on-failure";
        RestartSec = 15;
        StartLimitBurst = 5;
      };
      environment = graphicalEnv;
    };

    # --- AI Watchdog ---
    ai-watchdog = {
      description = "AI Task Pipeline Watchdog";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/ai-watchdog --daemon";
        Restart = "on-failure";
        RestartSec = 10;
      };
      environment = userEnv;
    };

    # --- Claude ESP Server ---
    claude-esp = {
      description = "Claude ESP - realtime sync to tablet";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${py}/bin/python3 ${launcher}/claude-esp-simple.py";
        Restart = "always";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- Claude Free API Auto ---
    claude-free-api-auto = {
      description = "Claude Free API auto-switch daemon";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/claude-free-api-auto daemon";
        Restart = "always";
        RestartSec = 60;
      };
    };

    # --- Claude Model Daemon ---
    claude-model-daemon = {
      description = "Claude model smart-switch daemon";
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/claude-model-daemon";
        Restart = "on-failure";
        RestartSec = 10;
      };
      environment = graphicalEnv;
    };

    # --- Claude Tablet Output ---
    claude-tablet-output = {
      description = "Claude output sync to tablet";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/claude-tablet-output";
        Restart = "always";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- Claude Token Tray ---
    claude-token-tray = {
      description = "Claude Token Monitor Tray";
      after = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/claude-token-tray";
        Restart = "on-failure";
        RestartSec = 10;
      };
      environment = graphicalEnv // { QT_QPA_PLATFORM = "xcb"; };
    };

    # --- GLM Proxy ---
    glm-proxy = {
      description = "GLM-4.7 Anthropic Proxy";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/glm-proxy";
        Restart = "on-failure";
        RestartSec = 3;
      };
      environment = userEnv;
    };

    # --- GLM Monitor ---
    glm-monitor = {
      description = "GLM Monitor Web Server";
      after = [ "glm-proxy.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/glm-monitor";
        Restart = "on-failure";
        RestartSec = 3;
      };
      environment = userEnv;
    };

    # --- Letta MCP Server ---
    letta-mcp = {
      description = "Letta Memory MCP Server";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/letta-mcp";
        Restart = "on-failure";
        RestartSec = 3;
      };
      environment = userEnv;
    };

    # --- Memory Evolution Engine ---
    memory-evolution = {
      description = "Memory Evolution - Self-Evolving AI Memory";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/memory-evolution-engine";
        Restart = "always";
        RestartSec = 10;
      };
      environment = userEnv;
    };

    # ============================================================
    # 二、Web 服务（持久守护进程）
    # ============================================================

    # --- HyperChat v5.2 ---
    hyperchat = {
      description = "HyperChat v5.2 - CRM + WeChat Browser (port 9098)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "${aiCluster}/hyperchat";
        ExecStart = "${py}/bin/python3 app_v2.py";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- Web Launcher ---
    launcher = {
      description = "Web Launcher PWA (port 9875)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = launcher;
        ExecStart = "${py}/bin/python3 launcher-server.py";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- Tablet Control Panel ---
    tablet-control-panel = {
      description = "Tablet Control Panel API (port 9876)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = launcher;
        ExecStart = "${py}/bin/python3 ${launcher}/tablet-control-api.py";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- LangChain Hub ---
    langchain-hub = {
      description = "LangChain Hub Web Viewer (port 8899)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "${aiCluster}/langchain-hub";
        ExecStart = "${aiCluster}/langchain-hub/venv/bin/python web_viewer.py";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- WeChat Web UI ---
    wechat-web = {
      description = "WeChat Message Review Web UI (port 9097)";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "${aiCluster}/wechat-sync";
        ExecStart = "${py}/bin/python3 web.py";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = userEnv;
    };

    # --- Whisper STT Server ---
    whisper = {
      description = "Whisper Speech-to-Text Server (port 8178)";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.whisper-cpp}/bin/whisper-server -m /mnt/ai/whisper/ggml-base.bin -l zh --host 127.0.0.1 --port 8178 -t 4";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # ============================================================
    # 三、工具服务
    # ============================================================

    # --- Clipboard Sync ---
    clipboard-sync-tablet = {
      description = "Clipboard Sync with Android Tablet";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/clipboard-sync-tablet";
        Restart = "on-failure";
        RestartSec = 30;
      };
      environment = graphicalEnv // { XDG_RUNTIME_DIR = "/run/user/1000"; };
    };

    # --- NumLock Guard ---
    numlock-guard = {
      description = "NumLock Guard - auto-enable numpad";
      after = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${localBin}/numlock-guard";
        Restart = "always";
        RestartSec = 10;
      };
    };

    # --- NumLock on startup ---
    numlock = {
      description = "Enable NumLock on startup";
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.numlockx}/bin/numlockx on";
        RemainAfterExit = true;
      };
    };

    # --- Tmux Claude Session ---
    tmux-claude = {
      description = "Tmux Claude work session";
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.tmux}/bin/tmux new-session -d -s claude-work -n Claude";
        ExecStop = "${pkgs.tmux}/bin/tmux kill-session -t claude-work";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # --- ydotoold ---
    ydotoold = {
      description = "ydotool daemon";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "always";
      };
    };

    # ============================================================
    # 四、定时任务 — Oneshot 服务
    # ============================================================

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
    browser-cookie-sync = {
      description = "Browser Cookie Sync";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/sync-all-browser-cookies";
      };
    };

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
    memory-dream = {
      description = "Memory Dream - AI memory consolidation";
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBin}/memory-dream";
      };
      environment = graphicalEnv;
    };

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

    # --- Memory Sync to NTFS (for Windows Continue) ---
    sync-memory-ntfs = {
      description = "Sync Claude memory to NTFS shared partition";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${localBin}/sync-memory-to-ntfs";
      };
      environment = userEnv;
    };
  };

  # ============================================================
  # 五、Timers
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

    browser-cookie-sync = {
      description = "Browser Cookie sync (every 5min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
      };
    };

    claude-orphan-killer = {
      description = "Claude orphan process killer (every 60s)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "60";
        AccuracySec = "10";
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
      description = "Image captioner (every 6h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/6:30:00";
        Persistent = true;
      };
    };

    letta-health-check = {
      description = "Letta health check (every 10min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    letta-health-guard = {
      description = "Letta health guard (every 5min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
    };

    letta-health-monitor = {
      description = "Letta health monitor (every 10min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    letta-sync = {
      description = "Letta session sync (every 5min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
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

    memory-dream = {
      description = "Memory dream consolidation (every 12h)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "12h";
        Persistent = true;
      };
    };

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

    sync-memory-ntfs = {
      description = "Sync memory to NTFS for Windows (every 2h + shutdown)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "2h";
        Persistent = true;
      };
    };
  };
}
