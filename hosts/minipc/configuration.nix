# minipc 基础配置 — 用于 nixos-anywhere 远程安装
# 安装完成后可逐步添加更多模块
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./disk-config.nix
  ];

  # 启动
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # WiFi 固件（LiveCD 最小 ISO 缺少无线驱动，安装后的系统需要完整固件）
  hardware.enableRedistributableFirmware = true;  # 包含 Intel/MediaTek 等可再分发固件
  # unfree 包许可（broadcom 固件 + 微信）
  # MediaTek USB WiFi6 适配器（ID 363e:7961，贴牌 VID 需手动绑定驱动）
  boot.kernelModules = [ "mt7921u" "mt7921e" ];
  # 开机自动绑定 363e:7961 到 mt7921u 驱动
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="363e", ATTR{idProduct}=="7961", RUN+="/bin/sh -c 'echo 363e 7961 > /sys/bus/usb/drivers/mt7921u/new_id 2>/dev/null || true'"
  '';

  # 防火墙开放 SSH
  networking.firewall.allowedTCPPorts = [ 22 ];

  # 网络
  networking.hostName = "minipc";
  networking.networkmanager.enable = true;
  # WiFi 由 NetworkManager 管理（无需单独启用 wpa_supplicant）

  # 固定 IP + hosts
  networking.extraHosts = ''
    192.168.2.100 tony
    192.168.2.101 minipc
    192.168.2.36  winpc windows
  '';

  # 代理（复用主机的 xray 代理服务，安装后需配置）
  # 方案一：直接使用主机代理（minipc 连主机局域网）
  # networking.proxy.httpProxy = "http://主机IP:7890";
  # 方案二：minipc 自己跑 xray（推荐，独立翻墙）
  # 取消下面注释即可启用 xray 代理
  #
  # environment.etc."xray/config.json".text = builtins.toJSON {
  #   inbounds = [{
  #     port = 7890; protocol = "http"; listen = "127.0.0.1";
  #   }];
  #   outbounds = [{
  #     protocol = "vless";
  #     settings.vnext = [{
  #       address = "cfyes.lxy1015.top"; port = 443;
  #       users = [{ id = "f99d11dd-5f7c-49a3-8ab7-80272d9b887e"; encryption = "none"; }];
  #     }];
  #     streamSettings = {
  #       network = "ws"; security = "tls";
  #       tlsSettings.serverName = "lx-us1.lxy1015.top";
  #       wsSettings = { path = "/liangxin/us"; headers.Host = "lx-us1.lxy1015.top"; };
  #     };
  #   }];
  # };

  # 时区
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # WiFi 预配置（安装后自动连接）
  networking.networkmanager.ensureProfiles.profiles = {
    "PDCN-KeTing" = {
      connection = {
        id = "PDCN - 客厅";
        type = "wifi";
        autoconnect = "true";
        autoconnect-priority = "10";
      };
      wifi = {
        ssid = "PDCN - 客厅";
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "1234567890";
      };
      ipv4 = {
        method = "manual";
        address1 = "192.168.2.101/24,192.168.2.1";
        dns = "192.168.2.1;8.8.8.8;";
      };
      ipv6.method = "disabled";
    };
  };

  # 用户
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    hashedPassword = "$6$6b3Jp2dPoHp0RCzR$RGFCacxJzYod/4QKqA8SnJMVTekttXc7K2ZIbN22mUGzdny4WTyRiCUfer7eRRSLdmoOAa67jYN9Hvsq.DwKG/";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHAFruJJ+bY1fAh05xg86ZHMCh+dMJUq6GjmH11yq2uN charlie@nixos"
    ];
  };

  # root SSH 密钥（nixos-anywhere 安装后需要）
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHAFruJJ+bY1fAh05xg86ZHMCh+dMJUq6GjmH11yq2uN charlie@nixos"
  ];

  # SSH（远程管理必须）
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true; # 首次登录允许密码，稳定后改 false
    };
  };

  # ========== 轻量桌面（LXQt — N100 友好，约 200MB 内存） ==========
  services.xserver.enable = true;
  services.xserver.desktopManager.lxqt.enable = true;
  services.displayManager.sddm.enable = true;

  # 音频
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # 中文输入法
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ qt6Packages.fcitx5-chinese-addons ];
  };

  # 手机配对
  programs.kdeconnect.enable = true;  # KDE Connect（手机互联）
  # ADB 由 systemd 258 自动处理 uaccess，只需安装 android-tools

  # 基础软件
  environment.systemPackages = with pkgs; [
    # 系统工具
    vim git htop curl wget
    pciutils usbutils wirelesstools iw
    xray
    android-tools       # ADB（scrcpy 需要）
    # 手机配对
    scrcpy              # 手机投屏+控制
    # 桌面应用
    pcmanfm-qt          # 文件管理器
    lxterminal          # 终端
    firefox             # 浏览器
    wechat-uos          # 微信
    input-leap          # 跨屏互控+剪贴板同步（与主机共享鼠标键盘+剪贴板）
  ];

  # 微信需要 unfree
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "broadcom-bt-firmware"
    "wechat-uos"
  ];

  # Nix 设置
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "charlie" ];
  };

  system.stateVersion = "25.11";
}
