{ config, pkgs, lib, ... }:

# Web / 终端持久服务

let
  py = config.charlie.sharedPythonEnv;
  home = "/home/charlie";
  launcher = "${home}/launcher";
  aiCluster = "/mnt/ai/ai-cluster";

  userEnv = {
    HOME = home;
    PYTHONUNBUFFERED = "1";
  };
in
{
  systemd.user.services = {

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
  };
}
