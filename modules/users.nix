{ config, pkgs, lib, ... }:

{
  # --- sops-nix 全局配置 ---
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/root/.config/sops/age/keys.txt";
    secrets = {
      charlie-hashedPassword = { neededForUsers = true; };
      minipc-hashedPassword = {};
      minipc-wifi-psk = {};
      # GLM / Z.AI API Key — 替代明文硬编码在脚本和 systemd service 中
      zai-api-key = {
        owner = "charlie";
        group = "users";
        mode = "0400";
      };
    };
    # 生成 env 格式文件供 macg-api.service / glm CLI 的 EnvironmentFile 使用
    templates."zai-api-key-env" = {
      owner = "charlie";
      group = "users";
      mode = "0400";
      path = "/run/secrets/zai-api-key-env";
      content = ''
        ANTHROPIC_API_KEY=${config.sops.placeholder."zai-api-key"}
        ANTHROPIC_AUTH_TOKEN=${config.sops.placeholder."zai-api-key"}
        ZAI_API_KEY=${config.sops.placeholder."zai-api-key"}
      '';
    };
  };

  # --- 用戶定義 ---
  users.users.charlie = {
    hashedPasswordFile = config.sops.secrets.charlie-hashedPassword.path;
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" "input" "uinput" "ydotool" ];
    shell = pkgs.zsh;
    # 声明式 SSH 公钥 — rebuild 后不丢失，免手动恢复 authorized_keys
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHAFruJJ+bY1fAh05xg86ZHMCh+dMJUq6GjmH11yq2uN"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOLV1tGBKQPdPZmGBRd2jzFoOggrB0obaOMxvJ+5tIhL windows-backup@spectrai"
    ];
  };

  # --- sudo 免密 ---
  security.sudo.extraRules = [{
    users = [ "charlie" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  # --- Zsh 配置 ---
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    interactiveShellInit = ''
      export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
      eval "$(direnv hook zsh)"
      /etc/nixos/scripts/letta-sync.sh &>/dev/null &
      # Wayland 会话下不设 GTK_IM_MODULE/QT_IM_MODULE（由 fcitx5 waylandFrontend 模块管理）
      # 手动设这两个变量会强制 X11 IM 桥接，导致 Floorp/微信等 Wayland 原生应用输入失效
      # 参见 lessons-learned.md 2026-04-18 条目
      export XMODIFIERS=@im=fcitx
    '';
    shellAliases = {
      ns = "sudo bash /etc/nixos/scripts/nixos-safe-upgrade.sh test";
      nixos-test = "sudo bash /etc/nixos/scripts/nixos-test-notify.sh pre-test && sudo bash /etc/nixos/scripts/nixos-safe-upgrade.sh test";
      nixos-confirm = "bash /etc/nixos/scripts/nixos-test-notify.sh notify";
      nixos-rollback = "sudo bash /etc/nixos/scripts/nixos-safe-upgrade.sh rollback";
      nixos-status = "bash /etc/nixos/scripts/nixos-safe-upgrade.sh status";
      nc = "sudo bash /etc/nixos/scripts/pin-stable-generation.sh restore 2>/dev/null; sudo nix-collect-garbage -d; sudo bash /etc/nixos/scripts/pin-stable-generation.sh restore 2>/dev/null";
      pin-stable = "sudo bash /etc/nixos/scripts/pin-stable-generation.sh pin";
      ai-log = "journalctl -u ollama.service -u openclaw-gateway.service -f";
      ai-up = "cd /mnt/ai/ai-cluster/dify/docker && docker compose up -d && cd /mnt/ai/ai-cluster/n8n && docker compose -p n8n2 up -d && cd /mnt/ai/ai-cluster/chroma && docker compose -p chroma2 up -d && cd /mnt/ai/ai-cluster/autogen && docker compose -p autogen up -d && cd /mnt/ai/ai-cluster/litellm && docker compose -p litellm up -d && cd /mnt/ai/ai-cluster/letta && docker compose -p letta up -d && echo 'AI 集群全部啟動'";
      ai-ps = "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'";
      distill = "cd /mnt/ai/ai-cluster/knowledge-distiller && docker compose -p distiller --profile run up --build";
      proxy-status = "cat /run/proxy-watchdog-state 2>/dev/null; systemctl status mihomo xray --no-pager | head -20";
      proxy-restart = "sudo systemctl restart mihomo && echo mihomo > /run/proxy-watchdog-state";
      proxy-log = "journalctl -u mihomo -u xray -u proxy-watchdog -f";
      proxy-ui = "echo 'Web UI: http://127.0.0.1:9090/ui'";
      nix-recover = "sudo /etc/nixos/scripts/recover-from-git.sh";
      full-restore = "sudo /etc/nixos/scripts/full-restore.sh";
      home-backup = "sudo /etc/nixos/scripts/home-backup.sh";
      nix-chat = "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/nixos-chat.py'";
      nix-seed = "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/seed-knowledge.py'";
      letta-sync = "/etc/nixos/scripts/letta-sync.sh";
      letta-obsidian = "nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/letta-obsidian-sync.py'";
      memory-sync = "/etc/nixos/scripts/memory-sync.sh";
      memory-fragments = "nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/memory/manage-fragments.py'";
      obsidian-letta = "flatpak run md.obsidian.Obsidian 'obsidian://open?vault=Obsidian&file=Letta-Memory%2FINDEX.md' 2>/dev/null || xdg-open 'obsidian://open?vault=Obsidian&file=Letta-Memory%2FINDEX.md' 2>/dev/null || true";
      obsidian-fragments = "flatpak run md.obsidian.Obsidian 'obsidian://open?vault=Obsidian&file=Memory-Fragments%2FINDEX.md' 2>/dev/null || xdg-open 'obsidian://open?vault=Obsidian&file=Memory-Fragments%2FINDEX.md' 2>/dev/null || true";
      obsidian = "flatpak run md.obsidian.Obsidian";
      dashboard = "echo 'Dashboard: http://127.0.0.1:9099' && xdg-open http://127.0.0.1:9099 2>/dev/null || true";
      q = "/etc/nixos/scripts/claude-interactive.sh";
      q-lite = "ANTHROPIC_BASE_URL=http://127.0.0.1:4000 ANTHROPIC_API_KEY=sk-litellm-charlie-2026 claude";
    };
  };

  # --- direnv 配置 ---
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # --- Tmux 配置 ---
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g status-left "#{?client_prefix,#[bg=red] WAIT ,#[bg=green] TMUX } "
      set -g mouse on
      set -g status-interval 1
      bind S setw synchronize-panes \; display "同步输入: #{?pane_synchronized,ON,OFF}"
      bind | split-window -h
      bind - split-window -v
    '';
  };

  # --- nix-ld：讓 JetBrains 插件等預編譯 binary 能在 NixOS 上運行 ---
  programs.nix-ld.enable = true;

  # --- VSCode 配置 ---
  # 注意：VSCode 配置管理需要 home-manager
  # 当前 NixOS 配置未启用 home-manager，暂用 systemd tmpfiles 方案
  # 详细方案对比见 pending-tasks.md
}
