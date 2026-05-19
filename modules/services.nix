{ config, pkgs, lib, ... }:
{
  # --- F3 救援模式 ---
  specialisation."F3 - Recovery".configuration = { config, pkgs, lib, ... }: {
    networking.networkmanager.enable = lib.mkForce true;
    nixpkgs.config.allowUnfree = lib.mkForce true;
    hardware.enableAllFirmware = lib.mkForce true;
    system.nixos.tags = [ "recovery" ];
    virtualisation.docker.enable = lib.mkForce false;
    services.ollama.enable = lib.mkForce false;
    virtualisation.libvirtd.enable = lib.mkForce false;
  };


  # --- 窗口假死检测 ---
  systemd.user.services.freeze-detector = {
    description = "Window Freeze Detector";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/freeze-detector.sh";
      Restart = "on-failure";
      RestartSec = 5;
    };

    environment = {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    };

  };


  # --- 自动备份用户数据 ---
  systemd.services.home-backup = {
    description = "Backup home data to /mnt/data";
    after = [ "mnt-data.mount" ];
    wants = [ "mnt-data.mount" ];
    path = [ pkgs.rsync pkgs.coreutils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "120";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/home-backup.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };

    environment.HOME = "/root";
  };


  systemd.timers.home-backup = {
    description = "Daily home backup timer (11:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 11:00:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };

  };


  # --- 系统健康监控 ---
  systemd.services.system-health-monitor = {
    description = "NixOS system health monitor";
    path = [ pkgs.bash pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.nix pkgs.findutils pkgs.libnotify ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "120";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/system-health-monitor.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };

  };


  systemd.timers.system-health-monitor = {
    description = "Daily system health check (09:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnCalendar = "*-*-* 09:00:00";
      Persistent = true;
    };

  };


  # --- 测试模式每日确认通知 ---
  systemd.user.services.nixos-test-notify = {
    description = "NixOS test mode confirmation reminder";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/nixos-test-notify.sh notify";
    };

    environment = {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
    };

  };


  systemd.user.timers.nixos-test-notify = {
    description = "Daily NixOS test confirmation popup";
    wantedBy = [ "graphical-session.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 10:00:00";
      Persistent = true;
    };

  };


  # --- Claude Code 对话自动同步到 Obsidian ---
  systemd.services.claude-to-obsidian = {
    description = "Sync Claude Code conversations to Obsidian";
    path = [ pkgs.bash pkgs.python313 pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "60";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/claude-to-obsidian.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };

  };


  systemd.timers.claude-to-obsidian = {
    description = "Sync Claude sessions to Obsidian every 6 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };

  };


  # --- Floorp 书签自动备份 ---
  systemd.services.floorp-bookmark-backup = {
    description = "Backup Floorp bookmarks to git";
    path = [ pkgs.bash pkgs.coreutils pkgs.sqlite ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/floorp-bookmark-backup.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };

  };


  systemd.timers.floorp-bookmark-backup = {
    description = "Daily Floorp bookmark backup (14:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 14:00:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };

  };



  # --- Cloudflare DDNS
  services.ddclient = {
    enable = true;
    package = pkgs.ddclient;
    protocol = "cloudflare";
    use = "web, web=ipify.org/";
    usev4 = "webv4, webv4=checkip.dyndns.com/";
    username = "token";
    zone = "charlie1990.dpdns.org";
    extraConfig = "password=CLOUDFLARE_API_TOKEN";
    domains = [ "charlie1990.dpdns.org" ];
    ssl = true;
    quiet = false;
    verbose = true;

    # Use configFile to bypass broken preStart (DynamicUser permission issue)
    configFile = pkgs.writeText "ddclient.conf" ''
      cache=/var/lib/ddclient/ddclient.cache
      foreground=YES
      use=web, web=icanhazip.com/
      login=token
      password=CLOUDFLARE_API_TOKEN
      protocol=cloudflare
      zone=charlie1990.dpdns.org
      host=charlie1990.dpdns.org
      ssl=yes
      quiet=no
      verbose=yes
    '';
  };

  systemd.services.ddclient.serviceConfig.Environment = lib.mkForce [
    "no_proxy=api.cloudflare.com,cloudflare.com,ipify.org"
  ];



}
