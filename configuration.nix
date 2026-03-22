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
    ./modules/essentials.nix
    ./modules/git.nix
  ];

  # --- 1. 底層硬體與網路：無縫切換防斷網 ---
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.usb-modeswitch.enable = true;

  # --- Realtek RTL8710BU WiFi 網卡：自動從 DISK 模式切換到 WiFi 模式 ---
  services.udev.extraRules = ''
    ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="${pkgs.usb-modeswitch}/bin/usb_modeswitch -v 0x0bda -p 0x1a2b -K 1"
  '';

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

  # --- Electron 渲染修復（NVIDIA + Wayland）---
  environment.variables.NIXOS_OZONE_WL = "1";
  environment.variables.ELECTRON_OZONE_PLATFORM_HINT = "auto";

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
    interactiveShellInit = ''
      # direnv hook（确保 .envrc 自动加载）
      eval "$(direnv hook zsh)"

      # Auto-sync Letta memory to Claude Code (background, max once/hour)
      /etc/nixos/scripts/letta-sync.sh &>/dev/null &

      # fcitx5 输入法：默认简体，每窗口独立状态
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
      export XMODIFIERS=@im=fcitx
    '';
    shellAliases = {
      ns = "sudo nixos-rebuild build --flake /etc/nixos#charlie && sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader";
      nc = "sudo nix-collect-garbage -d";
      ai-log = "journalctl -u ollama.service -u openclaw-gateway.service -f";
      ai-up = "cd /mnt/ai/ai-cluster/dify/docker && docker compose up -d && cd /mnt/ai/ai-cluster/n8n && docker compose -p n8n2 up -d && cd /mnt/ai/ai-cluster/chroma && docker compose -p chroma2 up -d && cd /mnt/ai/ai-cluster/autogen && docker compose -p autogen up -d && cd /mnt/ai/ai-cluster/litellm && docker compose -p litellm up -d && cd /mnt/ai/ai-cluster/letta && docker compose -p letta up -d && echo 'AI 集群全部啟動'";
      ai-ps = "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'";
      distill = "cd /mnt/ai/ai-cluster/knowledge-distiller && docker compose -p distiller --profile run up --build";
      proxy-status = "systemctl status mihomo";
      proxy-restart = "sudo systemctl restart mihomo";
      proxy-log = "journalctl -u mihomo -f";
      proxy-ui = "echo 'Web UI: http://127.0.0.1:9090/ui'";
      nix-recover = "sudo /etc/nixos/scripts/recover-from-git.sh";
      nix-chat = "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/nixos-chat.py'";
      nix-seed = "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/seed-knowledge.py'";
      letta-sync = "/etc/nixos/scripts/letta-sync.sh";
      letta-obsidian = "nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/letta-obsidian-sync.py'";
      memory-sync = "/etc/nixos/scripts/memory-sync.sh";
      memory-fragments = "nix-shell -p python313Packages.requests --run 'python3 /etc/nixos/scripts/memory/manage-fragments.py'";
      obsidian-letta = "xdg-open obsidian://open?vault=Obsidian&file=Letta-Memory%2FINDEX.md 2>/dev/null || true";
      obsidian-fragments = "xdg-open obsidian://open?vault=Obsidian&file=Memory-Fragments%2FINDEX.md 2>/dev/null || true";
      dashboard = "echo 'Dashboard: http://127.0.0.1:9099' && xdg-open http://127.0.0.1:9099 2>/dev/null || true";

      # Claude Code CLI 交互式选择（默认 LiteLLM）
      q = "/etc/nixos/scripts/claude-interactive.sh";
      q-lite = "ANTHROPIC_BASE_URL=http://127.0.0.1:4000 ANTHROPIC_API_KEY=sk-litellm-charlie-2026 claude";  # 直接走 LiteLLM
      q-third = "ANTHROPIC_BASE_URL=$ANTHROPIC_THIRD_PARTY_URL ANTHROPIC_API_KEY=$ANTHROPIC_THIRD_PARTY_TOKEN claude";  # 直接走第三方
    };
  };

  # direnv 配置
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # nix-ld：讓 JetBrains 插件等預編譯 binary 能在 NixOS 上運行
  programs.nix-ld.enable = true;

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
    code-cursor-fhs
    catppuccin-cursors.mochaDark

    # 核心修复：替换普通 vscode 为带渲染补丁的版本
    vscode-with-extensions

    # AI 相关依赖
    claude-code
    python313
    python313Packages.anthropic
    python313Packages.requests
    libnotify

    # 硬體診斷工具
    pciutils
    usbutils
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

  # fcitx5 環境變量（每窗口記住狀態）
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
  };

  # --- 7. 窗口假死检测 ---
  systemd.user.services.freeze-detector = {
    description = "Window Freeze Detector";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/freeze-detector.sh";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    };
  };

  # Nix 实验特性
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # 系统版本锁定
  system.stateVersion = "24.11";
}
