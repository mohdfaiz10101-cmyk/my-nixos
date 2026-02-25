{ config, pkgs, ... }: {
  # --- 用戶核心定義 ---
  users.users.charlie = {
    isNormalUser = true;
    description = "Charlie";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    group = "charlie";
    shell = pkgs.zsh;
    
    # 軟體矩陣：遵循 Git 分類邏輯
    packages = with pkgs; [
      # 基礎工具
      firefox git vim vscode wechat-uos
      wget curl input-remapper numlockx
      # 靈魂同步核心
      rclone 
    ];
  };

  users.groups.charlie = {};

  # --- 交互之魂：終端環境 ---
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      # 系統維護
      ns = "sudo nixos-rebuild switch --flake /etc/nixos";
      nc = "sudo nix-collect-garbage -d";
      nu = "nix flake update /etc/nixos";

      # --- 靈魂同步 (Essence Sync) ---
      # up: 發射邏輯。先拉取防衝突 -> Commit -> Push -> Rclone 同步到 Drive
      up = "cd /etc/nixos/essence && sudo git pull origin personal && sudo git add . && sudo git commit -m '🤖 注入增量邏輯' || true && sudo git push origin personal && rclone sync . gdrive:NixOS-Essence -P && printf '\n✅ 邏輯已發射並同步至 Drive\n'";
      
      # down: 拉回真理。從雲端獲取合併後的基座 -> 重建補丁目錄 (防止 Git 刪除空目錄)
      down = "cd /etc/nixos/essence && sudo git pull origin personal && sudo mkdir -p updates && printf '🧹 真理已拉回，本地碎屑已回收\n'";
    };
  };

  # --- 視聽隔離：Tmux 配置 ---
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g status-left "#{?client_prefix,#[bg=red] WAIT ,#[bg=green] TMUX } "
      set -g mouse on
      set -g status-interval 1
    '';
  };

  # --- 意識輸入：Fcitx5 整合 ---
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true; 
      addons = with pkgs; [ 
        fcitx5-rime
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        qt6Packages.fcitx5-configtool 
      ];
    };
  };
}