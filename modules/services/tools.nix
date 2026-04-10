{ config, pkgs, lib, ... }:

# 工具类持久服务（clipboard、numlock、tmux、ydotool）

let
  home = "/home/charlie";

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
  # --- GNOME Keyring (libsecret 依赖，Remmina 等应用需要) ---
  services.gnome.gnome-keyring = {
    enable = true;
  };
  systemd.user.services = {

    # --- Clipboard Sync ---
    clipboard-sync-tablet = {
      description = "Clipboard Sync with Android Tablet";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${home}/.local/bin/clipboard-sync-tablet";
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
        ExecStart = "${home}/.local/bin/numlock-guard";
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
  };
}
