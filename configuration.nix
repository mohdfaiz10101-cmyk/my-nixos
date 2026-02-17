{ config, pkgs, lib, ... }:

{
  imports = [ 
    ./hardware-configuration.nix
  ];

  # --- 引导与内核安全 ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  systemd.settings.Manager = {
    DefaultTimeoutStartSec = "10s";
  };

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # --- 生产力核心：Fcitx5 & Rime ---
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-rime
      fcitx5-gtk
      qt6Packages.fcitx5-chinese-addons
      qt6Packages.fcitx5-configtool
    ];
  };

  # --- 环境变量集中管理 ---
  environment.variables = {
    GTK_IM_MODULE = lib.mkForce "fcitx5";
    QT_IM_MODULE = lib.mkForce "fcitx5";
    XMODIFIERS = lib.mkForce "@im=fcitx5";
    SDL_IM_MODULE = lib.mkForce "fcitx5";
    GLFW_IM_MODULE = lib.mkForce "ibus";
    # 强制 VS Code 终端滚动锁定行为
    VSCODE_TERMINAL_SCROLL_ON_OUTPUT = "true";
  };

# 在 configuration.nix 中添加
nix.settings.experimental-features = [ "nix-command" "flakes" ];


  # --- 系统基础环境 ---
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- 磁盘挂载：G 盘/数据分区 ---
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/DE22F5F022F5CD91";
    fsType = "ntfs3";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" ];
  };

  # --- 用户空间：Charlie (Zsh/IDE) ---
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    # 视觉散热：高亮颜色定义
    interactiveShellInit = ''
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
    '';
  };

  users.users.charlie = {
    isNormalUser = true;
    description = "charlie";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # --- 软件包管理 (Unfree 链路) ---
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vscode
    wechat-uos
    flclash
    git
    wget
    curl
    oh-my-zsh
    firefox
  ];

  system.stateVersion = "26.05";
}