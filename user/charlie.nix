{ config, pkgs, ... }: {
  # --- 用户核心定义 ---
  users.users.charlie = {
    isNormalUser = true;
    description = "Charlie";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    group = "charlie";
    shell = pkgs.zsh;
    
    # 软件矩阵：严格空格分隔
    packages = with pkgs; [
      firefox       # 强制保留浏览器
      git
      vim
      wget
      curl
      vscode
      wechat-uos
      docker
      input-remapper
      numlockx
    ];
  };

  users.groups.charlie = {};

  # --- 交互之魂：终端环境 ---
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ns = "sudo nixos-rebuild switch --flake /etc/nixos";
      nc = "sudo nix-collect-garbage -d";
      nu = "nix flake update /etc/nixos";
    };
  };

programs.tmux = {
    enable = true;
    extraConfig = ''
      # 1. 視覺提示：按住 Ctrl+B 時，左下角會變色並顯示 "WAIT"
      set -g status-left "#{?client_prefix,#[bg=red] WAIT ,#[bg=green] TMUX } "

      # 2. 開啟滑鼠：可以直接用滑鼠點視窗、滾動螢幕（不用記快捷鍵）
      set -g mouse on

      # 3. 增加狀態欄反應速度
      set -g status-interval 1
    '';
  };



  # --- 意识输入：Fcitx5 神经通路 (25.11 终极适配) ---
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true; 
      addons = with pkgs; [ 
        fcitx5-rime
        qt6Packages.fcitx5-chinese-addons # 修复 1：包重命名
        fcitx5-gtk
        qt6Packages.fcitx5-configtool     # 修复 2：包重命名
      ];
    };
  };
}