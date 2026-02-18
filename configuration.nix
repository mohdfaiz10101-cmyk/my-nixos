{ config, pkgs, inputs, ... }: 
let
  # --- 逻辑探测：智能插槽 ---
  secretsFile = ./user-secrets.nix;
  secrets = if builtins.pathExists secretsFile 
            then import secretsFile 
            else { 
              password = null; # 留空，由 NixOS 提示设置或使用默认
              hashedPassword = null; 
            };
in
{
  imports = [ 
  ./hardware-configuration.nix
  ./modules/storage.nix
  ./modules/community.nix  # <--- 手动输入这一行
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
    autoNumlock = true; 
  };
  services.desktopManager.plasma6.enable = true;

  # --- 4. 区域与硬件权限 ---
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  
  services.input-remapper.enable = true; 
  
  users.users.charlie = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "docker" "input" "uinput" ];
    # 动态注入隐私：如果是你的 personal 分支，这里会自动生效
    initialPassword = if (secrets.password != null) then secrets.password else "nixos";
  };

  # --- 5. 实验性功能 (Flakes) ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.11"; 

  # --- 6. 高能豁免：Polkit 免密协议 ---
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

  # --- 7. 容器化应用管理 (已清理无效安装项) ---
  services.flatpak.enable = true;

  # --- 8. 系统环境补丁 ---
  environment.systemPackages = with pkgs; [
    numlockx       
    input-remapper 
    flatpak        
    git            # 确保 Git 始终可用
  ];
}