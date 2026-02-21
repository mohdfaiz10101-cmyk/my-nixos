{ config, pkgs, lib, inputs, ... }: 

let
  secretsFile = ./user-secrets.nix;
  secrets = if builtins.pathExists secretsFile then import secretsFile else { password = null; };
in
{
  # 1. 導入外部模組 (清單內只能放路徑)
  imports = [ 
    ./hardware-configuration.nix 
    ./proxy.nix    
    ./scripts.nix  
    ./modules/storage.nix # 建議導入掛載模組
    ./modules/git.nix     # 導入剛創建的 Git 分類模組
    ./modules/ai.nix      # 導入 AI 核心模組
  ];

  # 2. 系統代理設定 (必須放在 imports 之外)
  networking.proxy.default = "http://127.0.0.1:7890";
  networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # ================================================================
  # 1. 引導加載器 (GRUB)
  # ================================================================
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = false; 
    grub = {
      enable = true;
      device = "nodev";
      useOSProber = true; 
      efiSupport = true;
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

  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };





  # ================================================================
  # 2. 系統環境與服務
  # ================================================================
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  nixpkgs.config.allowUnfree = true;

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # 虛擬化與 Docker
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.package = pkgs.qemu_kvm;
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    proxies = {
      http-proxy = "http://127.0.0.1:7890";
      https-proxy = "http://127.0.0.1:7890";
      no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost";
    };
  };
  programs.virt-manager.enable = true; 

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # ================================================================
  # 3. 用戶配置
  # ================================================================
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" ]; 
    initialPassword = "nixos";
    shell = pkgs.zsh;
  };

  programs.zsh = {
    enable = true;
    shellAliases = {
      ns = "sudo nixos-rebuild switch --flake /etc/nixos#charlie";
    };
  };

  # ================================================================
  # 4. 軟體包與輸入法
  # ================================================================
  environment.systemPackages = (import ./packages.nix { inherit pkgs; }) ++ [
    pkgs.libreoffice-qt6-fresh
    pkgs.docker-compose
    pkgs.hunspell
    pkgs.tmux   # 後臺的後台下載神器
  ];

  environment.variables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    SDL_IM_MODULE = "fcitx";
    GDK_BACKEND = "x11"; 
    WEBKIT_DISABLE_COMPOSITING_MODE = "1";
    NIXOS_OZONE_WL = "1";
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ 
      qt6Packages.fcitx5-chinese-addons 
      fcitx5-rime 
      qt6Packages.fcitx5-configtool
    ];
  };

  # ================================================================
  # 5. Nix 設定與版本
  # ================================================================
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ 
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" 
      "https://cache.nixos.org/" 
    ];
  };

  system.stateVersion = "25.11"; 
}