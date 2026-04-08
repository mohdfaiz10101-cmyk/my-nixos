{ config, pkgs, lib, ... }:

# AI 相关持久守护服务

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
        ExecStart = "${py}/bin/python3 ${localBin}/glm-proxy";
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
        ExecStart = "${py}/bin/python3 ${localBin}/glm-monitor";
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
  };
}
