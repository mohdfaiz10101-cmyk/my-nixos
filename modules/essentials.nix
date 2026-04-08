{ config, pkgs, lib, ... }: {
  # 永不休眠/挂起
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.logind.settings.Login = { IdleAction = "ignore"; IdleActionSec = 0; };

  # --- Cockpit 系统 Web 管理面板（端口 9090）---
  services.cockpit = {
    enable = true;
    openFirewall = true;
  };

  # --- ttyd Web 终端（端口 7681）---
  systemd.services.ttyd = {
    description = "ttyd - Web Terminal (port 7681)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "charlie";
      ExecStart = "${pkgs.ttyd}/bin/ttyd -p 7681 -t fontSize=16 -t 'theme={\"background\":\"#1a1a2e\"}' ${pkgs.zsh}/bin/zsh";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # --- Tailscale VPN 组网（外网穿透）---
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- Syncthing 文件同步（全设备）---
  services.syncthing = {
    enable = true;
    user = "charlie";
    group = "users";
    dataDir = "/home/charlie";
    configDir = "/home/charlie/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;
    overrideFolders = false;
    settings.gui = {
      theme = "dark";
    };
  };

  # --- KDE Connect（剪贴板/通知/文件传输）---
  programs.kdeconnect.enable = true;

  # 注：环境包已移至 modules/packages.nix 统一管理
}
