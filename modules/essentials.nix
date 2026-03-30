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
  # 信任 Tailscale 接口，允许所有 CGNAT (100.64.0.0/10) 流量通过
  # 修复平板等通过 relay 中继连接的设备 SSH/VNC 超时问题
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- Syncthing 文件同步（全设备）---
  services.syncthing = {
    enable = true;
    user = "charlie";
    group = "users";
    dataDir = "/home/charlie";
    configDir = "/home/charlie/.config/syncthing";
    openDefaultPorts = true;  # 22000/TCP + 21027/UDP
    overrideDevices = false;  # 不覆盖通过 Web UI 添加的设备
    overrideFolders = false;  # 不覆盖通过 Web UI 添加的文件夹
    settings.gui = {
      theme = "dark";
    };
  };

  # --- KDE Connect（剪贴板/通知/文件传输）---
  programs.kdeconnect.enable = true;

  environment.systemPackages = let
    checkPkg = name: if builtins.hasAttr name pkgs then [ pkgs.${name} ] else [];
  in (checkPkg "uTools") ++ (checkPkg "utools") ++ [
    pkgs.appimage-run pkgs.wget pkgs.git pkgs.ntfs3g pkgs.ttyd
    pkgs.tailscale
    pkgs.sshpass pkgs.jq pkgs.yq-go
    pkgs.ulauncher  # 应用启动器（支持中文拼音搜索）
    # 语音输入工具链
    pkgs.whisper-cpp      # 本地语音识别（支持中文）
    pkgs.ffmpeg           # 音频录制和处理
    pkgs.ydotool          # Wayland 下模拟键盘输入
    pkgs.wl-clipboard     # Wayland 剪贴板工具
    pkgs.pulseaudio       # parecord 录音工具
  ];

  # 注释：POOL 盘的挂载和合并由 disk-pool.service 统一管理，不在这里配置
  # fileSystems."/mnt/storage_1.8t" 已移除，让 disk-pool 脚本自动处理

  systemd.services.openclaw-config-fix = {
    description = "AI Essence Service: Auto-config OpenClaw";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/lib/openclaw/data
      printf '{"gateway":{"mode":"local","port":18789},"models":{"default":"llama3","providers":{"ollama":{"base_url":"http://127.0.0.1:11434","enabled":true}}}}' > /var/lib/openclaw/openclaw.json
    '';
  };
}
