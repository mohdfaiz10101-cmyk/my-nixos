{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./modules/storage.nix
    ./user/charlie.nix
  ];

  # --- 1. 引导与内核 ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nixpkgs.config.allowUnfree = true;

  # --- 2. 网络与连接 ---
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # --- 3. 视觉散热：Plasma 6 架构 ---
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    autoNumlock = true; # 物理层开启 NumLock
  };
  services.desktopManager.plasma6.enable = true;

  # --- 4. 区域与硬件权限 ---
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  
  services.input-remapper.enable = true; # 鼠标手势硬件服务
  
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "docker" "input" "uinput" ];
  };

  # --- 5. 实验性功能 (Flakes) ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.11"; 

  # --- 6. 高能豁免：FlClash TUN 免密协议 ---
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel") && (
          action.id.indexOf("flclash") !== -1 || 
          action.id.indexOf("proxy") !== -1 ||
          action.id == "org.freedesktop.policykit.exec"
      )) {
        return polkit.Result.YES;
      }
    });
  '';

  # --- 7. 声明式软件：汽水音乐 ---
  services.flatpak.enable = true;
  system.activationScripts.flatpak-setup = {
    text = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      ${pkgs.flatpak}/bin/flatpak install -y flathub com.vmos.qishui
    '';
  };

  # --- 8. 系统环境补丁 ---
  environment.systemPackages = with pkgs; [
    numlockx       # 确保小键盘控制工具存在
    input-remapper # 鼠标手势配置工具
    flatpak        # 容器化应用管理
  ];
}