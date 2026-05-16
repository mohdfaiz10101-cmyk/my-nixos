

{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./modules/packages.nix     # 统一包管理
    ./modules/boot.nix
    ./modules/desktop.nix
    ./modules/users.nix
    ./modules/virtualization.nix
    ./modules/audio.nix
    ./modules/networking.nix
    ./modules/services.nix
    ./modules/services/litellm-docker.nix      # LiteLLM Docker Compose 服务
    ./modules/services/litellm-healthcheck.nix # LiteLLM 健康检查 + 自动拉起
    ./modules/storage.nix
    ./modules/ai.nix
    ./modules/proxy.nix
    ./modules/essentials.nix
    ./modules/git.nix
    ./modules/community.nix
    ./modules/productivity.nix
    ./scripts.nix
 #    ./modules/disk-pool.nix
    ./modules/auto-services.nix
    ./modules/python-env.nix
    ./modules/user-services.nix
    ./modules/browser.nix
    ./modules/security.nix
    ./modules/deepseek-auto-train.nix  # DeepSeek 自动训练
    ./modules/tablet-proxy.nix         # 平板代理自动切换
    ./modules/docker-nat-fix.nix       # Docker 容器 NAT 转发修复
    ./modules/i3.nix             # i3 WM（X11，替代 Hyprland，规避 NVIDIA 挂死）
    ./modules/barrier.nix
    ./modules/services/frp.nix         # FRP 内网穿透服务端
    ./modules/data-recovery.nix        # 智能数据恢复系统
    ./modules/auto-recovery.nix        # 启动和定时触发
    ./modules/initrd-ssh.nix           # initrd SSH 远程救援
    ./modules/opencode-recovery.nix    # OpenCode Recovery Mode
  ];

services.openssh = {
  enable = true;
  settings = {
   PermitRootLogin = lib.mkForce "yes";
  };
};

  # --- 字体（Nerd Font 图标 + 中文）---
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    noto-fonts
    noto-fonts-cjk-serif
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # --- 硬件固件 ---
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.usb-modeswitch.enable = true;

  # --- USB 网络设备支持（平板/手机 USB Tethering）---
  boot.kernelModules = [ "rndis_host" "cdc_ether" "cdc_ncm" "cdc_mbim" ];

  # --- 时区和语言 ---
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # --- 输入法 fcitx5 ---
  # !! DO NOT CHANGE waylandFrontend !! auto-save 已多次误改此值
  # waylandFrontend = true 是必须的：fcitx5 注册 Wayland text-input-v3
  # Kitty + OpenCode TUI 中文输入依赖此项，改为 false 会导致输入法失效
  # GTK_IM_MODULE/QT_IM_MODULE 在 desktop.nix sessionVariables 显式设置
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true; # PROTECTED: DO NOT CHANGE TO FALSE
      addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-rime
        fcitx5-gtk
        qt6Packages.fcitx5-configtool
      ];
    };
  };

  # 包管理已移至 modules/packages.nix 统一管理

  # --- Nix 自动垃圾回收 + 磁盘保护 ---
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "-d --delete-older-than 7d";  # -d: 删除旧 system generations; 7d: 保留近 7 天
  };
  nix.extraOptions = ''
    min-free = ${toString (512 * 1024 * 1024)}
    max-free = ${toString (2 * 1024 * 1024 * 1024)}
  '';

  # --- Nix 设置 ---
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = "auto";
    cores = 0;
    auto-optimise-store = false;
    substituters = lib.mkForce [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  # === LiteLLM Docker 服务配置 ===
  services.litellm-docker = {
    enable = true;
    composeDir = "/mnt/ai-cluster/litellm";  # ✓ 修正路径（移除多余的 /ai）
    port = 4000;
  };

  system.stateVersion = "26.05";

  # ========== 无 GPU 紧急恢复模式 ==========
  # 用途：显卡驱动崩溃/Wayland 卡死时，从 GRUB 选此项进纯 TTY 修复
  # 保留：SSH、网络、Docker、Claude Code、OpenCode 全部可用
  # 使用：开机 GRUB 选 "NixOS — noGUI (Emergency)" 进入
  specialisation.noGUI.configuration = {
    # 禁用 NVIDIA 驱动（改用 modesetting 基础驱动，TTY 可用）
    services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
    hardware.nvidia.modesetting.enable = lib.mkForce false;
    boot.extraModprobeConfig = lib.mkForce "";
    # nomodeset: 禁用 GPU KMS，使用 EFI/VESA framebuffer（使 fbterm 可用）
    boot.kernelParams = lib.mkForce [ "nomodeset" "systemd.unit=multi-user.target" ];

    # 禁用桌面环境（KDE/SDDM/Sunshine 全部关闭）
    services.xserver.enable = lib.mkForce false;
    services.displayManager.sddm.enable = lib.mkForce false;
    services.desktopManager.plasma6.enable = lib.mkForce false;
    services.sunshine.enable = lib.mkForce false;
    services.displayManager.autoLogin.enable = lib.mkForce false;

    # 禁用 Wayland 相关环境变量
    environment.variables.NIXOS_OZONE_WL = lib.mkForce "";
    environment.variables.ELECTRON_OZONE_PLATFORM_HINT = lib.mkForce "";

    # 禁用依赖桌面的服务
    services.flatpak.enable = lib.mkForce false;
    xdg.portal.enable = lib.mkForce false;

    # TTY1 自动登录 charlie（无 SDDM 时生效）
    services.getty.autologinUser = lib.mkForce "charlie";

    # fbterm 已移至 desktop.nix 全局安装（TTY 中文支持）
    # noGUI 下 console 字体（基础 Unicode 显示）
    console.font = lib.mkForce "ter-v32n";
    console.packages = lib.mkForce (with pkgs; [ terminus_font ]);

    # 保留：SSH、网络、Docker — 修复用
    # （这些模块已在 imports 中，无需重复声明）
  };
}
