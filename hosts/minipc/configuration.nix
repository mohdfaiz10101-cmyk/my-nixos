# minipc 基础配置 — 用于 nixos-anywhere 远程安装
# 安装完成后可逐步添加更多模块
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./disk-config.nix
    ./docker.nix
  ];

  # --- sops-nix 加密 secrets ---
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/home/charlie/.config/sops/age/keys.txt";
    secrets = {
      minipc-hashedPassword = { neededForUsers = true; };
      minipc-wifi-psk = {};
    };
  };

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
    # 禁用 bestechnic MicLink 语音助手键盘的 HID 键盘输入（防止乱输字）
    SUBSYSTEM=="input", ATTRS{idVendor}=="3151", ATTRS{idProduct}=="20ab", ENV{ID_INPUT_KEYBOARD}="0", ENV{ID_INPUT_KEY}="0"
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
  # 注意：代理 secrets 需要在 sops.secrets 中声明后引用
  #
  # sops.secrets = {
  #   vless-uuid = {};
  #   proxy-server-address = {};
  #   proxy-server-port = {};
  #   proxy-tls-serverName = {};
  #   proxy-ws-path = {};
  #   proxy-ws-host = {};
  # };
  # systemd.services.xray = { ... }; # 类似主机的 proxy.nix 配置

  # 时区
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # WiFi 预配置（安装后自动连接）
  # WiFi PSK 从 sops secret 文件读取，通过 systemd 服务写入 NM connection
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
        psk = "$WIFI_PSK";  # placeholder, replaced by systemd service
      };
      ipv4 = {
        method = "manual";
        address1 = "192.168.2.101/24,192.168.2.1";
        dns = "192.168.2.1;8.8.8.8;";
      };
      ipv6.method = "disabled";
    };
  };

  # 用 sops 解密后的 PSK 覆盖 NM connection 文件
  systemd.services.nm-wifi-psk = {
    description = "Inject WiFi PSK from sops into NetworkManager";
    after = [ "network-manager.service" "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      PSK_FILE="${config.sops.secrets.minipc-wifi-psk.path}"
      CONN_FILE="/etc/NetworkManager/system-connections/PDCN-KeTing.nmconnection"
      if [ -f "$PSK_FILE" ] && [ -f "$CONN_FILE" ]; then
        PSK=$(cat "$PSK_FILE")
        ${pkgs.gnused}/bin/sed -i "s|^psk=.*|psk=$PSK|" "$CONN_FILE"
        ${pkgs.networkmanager}/bin/nmcli connection reload 2>/dev/null || true
      fi
    '';
  };

  # wheel 组免密 sudo（远程运维必须）
  security.sudo.wheelNeedsPassword = false;

  # 用户
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    hashedPasswordFile = config.sops.secrets.minipc-hashedPassword.path;
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
    # 构建时全局代理（sops-nix Go 模块下载需要翻墙）
    env-vars = {
      http_proxy = "http://192.168.2.100:7890";
      https_proxy = "http://192.168.2.100:7890";
      HTTP_PROXY = "http://192.168.2.100:7890";
      HTTPS_PROXY = "http://192.168.2.100:7890";
      no_proxy = "127.0.0.0/8,192.168.0.0/16,localhost";
      GOPROXY = "https://goproxy.cn,https://proxy.golang.org,direct";
    };
  };
  nix.buildMachines = [];  # 本地构建

  system.stateVersion = "25.11";
}
