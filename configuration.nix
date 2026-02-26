{ config, pkgs, lib, inputs, ... }:

let
  secretsFile = ./user-secrets.nix;
  secrets = if builtins.pathExists secretsFile then import secretsFile else { password = null; };
in
{
  imports = [
    ./hardware-configuration.nix
    ./modules/storage.nix
    ./modules/ai.nix
    ./modules/proxy.nix
  ];

  # --- 1. 底層硬體與網路：無縫切換防斷網 ---
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # --- NVIDIA RTX 3060 Ti 驅動 ---
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # --- 桌面環境：GNOME + GDM ---
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # --- 鼠標主題：Catppuccin Mocha Dark ---
  environment.variables.XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
  environment.variables.XCURSOR_SIZE = "24";

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # --- 2. 引導與磁盤：雙系統與防掉盤機制 ---
  boot.loader = {
    efi.canTouchEfiVariables = false;
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "nodev";
      useOSProber = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 3;
      extraEntries = lib.mkOrder 0 ''
        menuentry "Windows 11 (Physical NVMe Fix)" {
          insmod part_gpt
          insmod fat
          insmod search_fs_uuid
          insmod chain
          search --fs-uuid --set=root FA67-631E
          chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        }
      '';
    };
  };

  # --- F3 救援模式 ---
  specialisation."F3 - Recovery Stable Mode".configuration = { config, pkgs, lib, ... }: {
    networking.networkmanager.enable = lib.mkForce true;
    nixpkgs.config.allowUnfree = lib.mkForce true;
    hardware.enableAllFirmware = lib.mkForce true;
    system.nixos.tags = [ "recovery-stable" ];
  };

  # 磁盤自動掛載
  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };

  # --- 3. 虛擬化與 Docker ---
  services.flatpak.enable = true;
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/ai/docker";
      proxies = {
        http-proxy = "http://127.0.0.1:7890";
        https-proxy = "http://127.0.0.1:7890";
        no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost,11434,18789";
      };
    };
  };
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # --- 4. 用戶環境與終端 ---
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" "input" "uinput" ];
    shell = pkgs.zsh;
  };

  security.sudo.extraRules = [{
    users = [ "charlie" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ns = "sudo nixos-rebuild build --flake /etc/nixos#charlie && sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader";
      nc = "sudo nix-collect-garbage -d";
      ai-log = "journalctl -u ollama.service -u openclaw-gateway.service -f";
      proxy-status = "systemctl status mihomo";
      proxy-restart = "sudo systemctl restart mihomo";
      proxy-log = "journalctl -u mihomo -f";
      proxy-ui = "echo 'Web UI: http://127.0.0.1:9090/ui'";
      nix-recover = "sudo /etc/nixos/scripts/recover-from-git.sh";
    };
  };

  # direnv 配置
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # --- 5. 開發矩陣與環境變數 ---
  environment.systemPackages = with pkgs; [
    # 基础工具
    firefox
    git
    jetbrains.idea
    docker-compose
    tmux
    nodejs_22
    ntfs3g
    direnv
    wechat-uos
    cursor-cli
    catppuccin-cursors.mochaDark

    # 核心修复：替换普通 vscode 为带渲染补丁的版本
    vscode-with-extensions

    # AI 相关依赖
    python313
    python313Packages.anthropic
  ];

  # --- 6. 輸入法與區域設定 ---
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons
      fcitx5-rime
      qt6Packages.fcitx5-configtool
    ];
  };

  # Nix 实验特性
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # 系统版本锁定
  system.stateVersion = "24.11";
}
