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
    ./modules/services/litellm-docker.nix  # LiteLLM Docker Compose 服务（新增）
    ./modules/storage.nix
    ./modules/ai.nix
    ./modules/proxy.nix
    ./modules/essentials.nix
    ./modules/git.nix
    ./modules/community.nix
    ./modules/productivity.nix
    ./scripts.nix
    ./modules/disk-pool.nix
    ./modules/auto-services.nix
    ./modules/python-env.nix
    ./modules/user-services.nix
    ./modules/browser.nix
    ./modules/security.nix
    ./modules/deepseek-auto-train.nix  # DeepSeek 自动训练
    ./modules/tablet-proxy.nix         # 平板代理自动切换
    ./modules/docker-nat-fix.nix       # Docker 容器 NAT 转发修复
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
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
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

  # === LiteLLM Docker 服务配置（可选）===
  # 开启后会在开机时自动启动 LiteLLM 容器
  # 需要指定 docker-compose.yml 的位置
  # 取消注释以下行并修改 composeDir 路径
  #
  # services.litellm-docker = {
  #   enable = true;
  #   composeDir = "/mnt/ai-cluster/litellm";  # 改为实际路径
  #   port = 4000;
  # };

  system.stateVersion = "26.05";
}
