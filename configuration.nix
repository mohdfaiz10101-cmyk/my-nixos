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
  ];

  # --- 1. 底層硬體與網路：無縫切換防斷網 ---
  # 強制允許非自由軟體，這是載入 Wi-Fi 驅動的絕對前提
  nixpkgs.config.allowUnfree = true;
  # 載入所有閉源韌體 (解決拔掉手機後找不到 Wi-Fi 的問題)
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # --- NVIDIA RTX 3060 Ti 驅動 ---
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # GA104 用閉源驅動更穩定
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # --- 桌面環境：GNOME + GDM ---
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true; # 桌面環境網路總管

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
      
      # ⚠️ 核心加固：強制寫入萬用引導路徑 /EFI/BOOT/BOOTX64.EFI
      # 徹底根治華碩 BIOS 升級或重置後「認不到硬碟」的毛病
      efiInstallAsRemovable = true;

      # 限制 GRUB 只保留最近 3 個 Generation，防止 EFI 分區爆滿
      configurationLimit = 3;

      # Windows 11 物理直通引導
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

  # --- F3 救援模式：固化當前穩定狀態為獨立開機選項 ---
  specialisation."F3 - Recovery Stable Mode".configuration = { config, pkgs, lib, ... }: {
    # 強制開啟網路
    networking.networkmanager.enable = lib.mkForce true;
    # 強制允許非自由驅動
    nixpkgs.config.allowUnfree = lib.mkForce true;
    hardware.enableAllFirmware = lib.mkForce true;
    # 鎖定與主系統相同的核心模組，確保硬體驅動一致
    system.nixos.tags = [ "recovery-stable" ];
  };

  # 磁盤自動掛載 (保留 nofail 防止開機卡死)
  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };

  # --- 3. 虛擬化與 Docker (算力穿透優化) ---
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
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

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      # 安全重構：先 build 驗證，成功後才 switch
      ns = "sudo nixos-rebuild build --flake /etc/nixos#charlie && sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader";
      # 清理時保留被釘住的 Generation（pinned GC root 不會被刪）
      nc = "sudo nix-collect-garbage -d";
      ai-log = "journalctl -u ollama.service -u openclaw-gateway.service -f";
    }; 
  };

  # --- 5. 開發矩陣與環境變數 ---
  environment.systemPackages = with pkgs; [
    firefox
    git
    vscode
    jetbrains.idea # 明確指定社區免費版，避免授權報錯
    docker-compose
    tmux
    nodejs_22
    ntfs3g
    direnv
  ];

  # direnv：進入目錄時自動載入 .envrc 環境變數
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.11"; 
}