{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware-configuration.nix   # 硬件底层
    ./modules/storage.nix          # 4T 硬盘
    ./user/charlie.nix             # Zsh 与 输入法
  ];

  # 基础设定
  networking.hostName = "nixos";
  time.timeZone = "Asia/Shanghai";
  
  # 开启实验性功能 (Flakes 核心)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11"; 
}
