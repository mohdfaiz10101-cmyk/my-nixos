{ config, pkgs, lib, inputs, ... }: 
let
  secretsFile = ./user-secrets.nix;
  secrets = if builtins.pathExists secretsFile then import secretsFile else { password = null; };
in
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = false; 
    grub = {
      enable = true;
      device = "nodev";
      useOSProber = true;
      efiSupport = true;
    };
    grub.extraEntries = lib.mkOrder 0 ''
      menuentry "Windows 11 (Fixed Path)" {
        insmod part_gpt
        insmod fat
        insmod search_fs_uuid
        insmod chain
        search --fs-uuid --set=root FA67-631E
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  nixpkgs.config.allowUnfree = true;

  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    autoNumlock = true; 
  };
  services.desktopManager.plasma6.enable = true;

  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];
    initialPassword = "nixos";
  };

  environment.systemPackages = with pkgs; [
    git
    os-prober
    flclash         
    google-chrome   
    fastfetch       
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.nju.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    connect-timeout = 3;
    download-attempts = 5;
    fallback = true;
  };

  system.stateVersion = "25.11"; 
}