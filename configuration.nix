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
    ./modules/community.nix
    ./modules/productivity.nix
    ./scripts.nix
    ./modules/disk-pool.nix
    ./modules/auto-services.nix
    ./modules/python-env.nix
    ./modules/user-services.nix
    ./modules/browser.nix      # 浏览器配置声明式管理
  ];

  # --- 1. 底層硬體與網路：無縫切換防斷網 ---
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.usb-modeswitch.enable = true;

  # --- zram 壓縮 Swap（內存不足 16G 時的安全網）---
  zramSwap = {
    enable = true;
    algorithm = "zstd";       # 最佳壓縮率/速度平衡
    memoryPercent = 100;      # 用 100% RAM 做 zram（壓縮後等效 ~32-48GB swap）
  };

  # --- Realtek RTL8710BU WiFi 網卡：自動從 DISK 模式切換到 WiFi 模式 ---
  # --- Sunshine 虚拟输入设备权限 ---
  services.udev.extraRules = ''
    ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="${pkgs.usb-modeswitch}/bin/usb_modeswitch -v 0x0bda -p 0x1a2b -K 1"
    KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", MODE="0660", GROUP="input"
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

  # --- Sunshine 远程串流服务器（Moonlight 客户端连接）---
  # --- Waydroid Android 容器 ---
  virtualisation.waydroid.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;       # 登录图形会话后自动启动
    capSysAdmin = true;     # KDE Wayland 必须，用于 DRM/KMS 屏幕捕获
    openFirewall = true;    # 自动开放 47984-48010 等端口
  };

  # --- 桌面環境：KDE Plasma + SDDM（自動登入）---
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.sddm.settings.General.Numlock = "on";
  services.displayManager.defaultSession = "plasma";
  services.displayManager.autoLogin = {
    enable = true;
    user = "charlie";
  };
  services.desktopManager.plasma6.enable = true;
  # services.desktopManager.cosmic.enable = true; # 上游 cosmic-edit 哈希不匹配，等修复
  # services.displayManager.cosmic-greeter.enable = false;

  # --- 鼠標主題：Catppuccin Mocha Dark ---
  environment.variables.XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
  environment.variables.XCURSOR_SIZE = "24";

  # --- Electron 渲染修復（NVIDIA + Wayland）---
  environment.variables.NIXOS_OZONE_WL = "1";
  environment.variables.ELECTRON_OZONE_PLATFORM_HINT = "auto";

  # --- XDG 缓存重定向到池分区（减轻根分区压力）---
  # 注意：nix 缓存不能放 mergerfs（SQLite 文件锁不兼容 FUSE），单独 symlink 到本地
  environment.variables.XDG_CACHE_HOME = "/mnt/pool/offload/cache-charlie";
  system.activationScripts.nix-cache-local = {
    text = ''
      POOL_NIX="/mnt/pool/offload/cache-charlie/nix"
      LOCAL_NIX="/home/charlie/.cache/nix"
      mkdir -p "$LOCAL_NIX"
      chown charlie:users "$LOCAL_NIX"
      if [ -d "$POOL_NIX" ] && [ ! -L "$POOL_NIX" ]; then
        # 合并已有数据到本地
        cp -an "$POOL_NIX/." "$LOCAL_NIX/" 2>/dev/null || true
        rm -rf "$POOL_NIX" 2>/dev/null || true
      fi
      [ -L "$POOL_NIX" ] || ln -sf "$LOCAL_NIX" "$POOL_NIX"
      chown -h charlie:users "$POOL_NIX"
    '';
    deps = [ "users" ];
  };

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # ⚡ 启动优化（SPE-31）：NetworkManager-wait-online 默认等待所有接口就绪（耗时 6.5s）
  # 禁用该服务，AI 服务已改为延迟启动，不再需要此等待
  systemd.services.NetworkManager-wait-online.enable = false;

  # LAN 固定设备名称解析
  networking.extraHosts = ''
    192.168.2.100 tony nixos
    192.168.2.101 minipc
    192.168.2.36  winpc windows
  '';

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # --- 音频修复：ALC897 需要 model hint ---
  # --- ydotool 文字输入守护进程（Voxtype 依赖）---
  programs.ydotool.enable = true;

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=generic
  '';

  # --- 2. 引導與磁盤：雙系統與防掉盤機制 ---
  boot.loader = {
    efi.canTouchEfiVariables = false;
    efi.efiSysMountPoint = "/boot/efi";
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "nodev";
      useOSProber = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 3;
      theme = pkgs.sleek-grub-theme;
      gfxmodeEfi = "1920x1080";
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

  # --- F3 救援模式（最小化，只保留网络 + Claude + git）---
  specialisation."F3 - Recovery".configuration = { config, pkgs, lib, ... }: {
    networking.networkmanager.enable = lib.mkForce true;
    nixpkgs.config.allowUnfree = lib.mkForce true;
    hardware.enableAllFirmware = lib.mkForce true;
    system.nixos.tags = [ "recovery" ];
    # 救援模式禁用非必要服务，防止干扰
    virtualisation.docker.enable = lib.mkForce false;
    services.ollama.enable = lib.mkForce false;
    virtualisation.libvirtd.enable = lib.mkForce false;
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
      data-root = "/var/lib/docker";
      registry-mirrors = [
        "https://docker.1ms.run"
        "https://docker.xuanyuan.me"
      ];
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
    hashedPassword = "$y$j9T$dQVrueHAipmLfNdbhfOP.0$uPAMY96g28GVwgQLsUOcEPUzCBJWlakEhvcSVUhVge7";
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" "input" "uinput" "ydotool" ];
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
      # 用户本地工具 PATH
      export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

      # direnv hook（确保 .envrc 自动加载）
      eval "$(direnv hook zsh)"

      # Auto-sync Letta memory to Claude Code (background, max once/hour)
      /etc/nixos/scripts/letta-sync.sh &>/dev/null &


      # fcitx5 环境变量已提升到 sessionVariables，此处仅作终端覆盖（确保优先级）
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
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
      obsidian-letta = "xdg-open obsidian://open?vault=Obsidian&file=Letta-Memory%2FINDEX.md 2>/dev/null || true";
      obsidian-fragments = "xdg-open obsidian://open?vault=Obsidian&file=Memory-Fragments%2FINDEX.md 2>/dev/null || true";
      dashboard = "echo 'Dashboard: http://127.0.0.1:9099' && xdg-open http://127.0.0.1:9099 2>/dev/null || true";

      # Claude Code CLI 交互式选择（默认 LiteLLM）
      q = "/etc/nixos/scripts/claude-interactive.sh";
      q-lite = "ANTHROPIC_BASE_URL=http://127.0.0.1:4000 ANTHROPIC_API_KEY=sk-litellm-charlie-2026 claude";  # 直接走 LiteLLM
    };
  };

  # direnv 配置
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Tmux 配置
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g status-left "#{?client_prefix,#[bg=red] WAIT ,#[bg=green] TMUX } "
      set -g mouse on
      set -g status-interval 1

      # 一键开启/关闭同步输入（广播到所有面板）
      bind S setw synchronize-panes \; display "同步输入: #{?pane_synchronized,ON,OFF}"

      # 快速分屏
      bind | split-window -h
      bind - split-window -v
    '';
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
    # Snipaste 风格贴图工具
    feh          # 轻量级图片查看器（置顶、无边框）
    xdotool      # X11 窗口操作工具
    wmctrl       # 窗口管理工具


    # 核心修复：替换普通 vscode 为带渲染补丁的版本
    vscode-with-extensions

    # AI 相关依赖
    claude-code
    python313
    python313Packages.anthropic
    python313Packages.requests
    libnotify

    # 浏览器
    inputs.zen-browser.packages.x86_64-linux.default
    floorp-bin
    google-chrome

    # 通讯
    telegram-desktop

    # 手机投屏与工具
    scrcpy
    android-tools
    flclash

    # 系统工具
    wl-clipboard
    translate-shell
    (tesseract5.override { enableLanguages = [ "eng" "chi_sim" "chi_tra" "jpn" "kor" ]; })
    imagemagick
    zenity
    fastfetch
    htop
    vim
    wget
    curl
    rclone
    input-remapper
    numlockx
    inotify-tools  # 文件监控（claude-watch 脚本需要）

    # 终端
    # 远程桌面 + 浏览器自动化 + 轻量图片查看器
    remmina
    moonlight-qt
    rustdesk-flutter
    kdePackages.krfb
    playwright-mcp
    imv
    warp-terminal
    kitty

    # 硬體診斷工具
    pciutils
    usbutils

    # KDE 圆角主题套件
    catppuccin-kde
    catppuccin-kvantum
    catppuccin-gtk
    kdePackages.qtstyleplugin-kvantum
    tela-icon-theme
    tela-circle-icon-theme
    papirus-icon-theme
    keepassxc

    # 办公套件
    libreoffice-qt6-fresh
    
    # 文档处理工具链
    pandoc
    hunspell
    hunspellDicts.en_US
    sqlcipher
    
    # LaTeX 中文 PDF（pandoc → pdf 输出）
    (texlive.combine {
      inherit (texlive)
        scheme-small
        collection-langchinese
        collection-fontsrecommended
        fancyhdr titlesec geometry enumitem
        xcolor hyperref bookmark;
    })

    # Spectacle OCR 翻译支持
    (kdePackages.spectacle.override {
      tesseractLanguages = [ "eng" "chi_sim" "chi_tra" "jpn" "kor" ];
    })
    # 应用商店
    kdePackages.discover
    packagekit
  ];

  # --- 6. 輸入法與區域設定 ---
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-rime
        fcitx5-gtk
        qt6Packages.fcitx5-configtool
      ];
    };
  };

  # KDE 不需要禁用 ibus，fcitx5 直接接管

  # fcitx5 環境變量（每窗口記住狀態）
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";  # JetBrains 等 GUI 应用需要此变量
    INPUT_METHOD = "fcitx";
    GLFW_IM_MODULE = "ibus";  # Kitty 等 GLFW 应用需要此变量才能用 fcitx5
    # 代理由 modules/proxy.nix (networking.proxy) 统一管理
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

  # --- 8. 自动备份用户数据（每天一次，防重装丢失）---
  systemd.services.home-backup = {
    description = "Backup home data to /mnt/data";
    after = [ "mnt-data.mount" ];
    requires = [ "mnt-data.mount" ];
    path = [ pkgs.rsync pkgs.coreutils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/home-backup.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    environment.HOME = "/root";
  };

  systemd.timers.home-backup = {
    description = "Daily home backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # --- 9. 系统健康监控（磁盘 + 备份 + 测试状态）---
  systemd.services.system-health-monitor = {
    description = "NixOS system health monitor";
    path = [ pkgs.bash pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.nix pkgs.findutils pkgs.libnotify ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/system-health-monitor.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.system-health-monitor = {
    description = "Daily system health check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # --- 10. 测试模式每日确认通知 ---
  systemd.user.services.nixos-test-notify = {
    description = "NixOS test mode confirmation reminder";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/nixos-test-notify.sh notify";
    };
    environment = {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
    };
  };

  systemd.user.timers.nixos-test-notify = {
    description = "Daily NixOS test confirmation popup";
    wantedBy = [ "graphical-session.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 10:00:00";
      Persistent = true;
    };
  };

  # --- 11. Claude Code 对话自动同步到 Obsidian ---
  systemd.services.claude-to-obsidian = {
    description = "Sync Claude Code conversations to Obsidian";
    path = [ pkgs.bash pkgs.python313 pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/claude-to-obsidian.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.claude-to-obsidian = {
    description = "Sync Claude sessions to Obsidian every 6 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };

  # --- 11. Floorp 书签自动备份（每天 + git 追踪）---
  systemd.services.floorp-bookmark-backup = {
    description = "Backup Floorp bookmarks to git";
    path = [ pkgs.bash pkgs.coreutils pkgs.sqlite ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/floorp-bookmark-backup.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.floorp-bookmark-backup = {
    description = "Daily Floorp bookmark backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };

  # --- SSH 服务（Vast.ai GPU 出租必需）---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      X11Forwarding = false;
    };
    ports = [ 22 ];
  };

  networking.firewall.allowedTCPPorts = [ 22 5900 7681 9090 9098 9875 9876 3002 ];
  # --- Nix 自动垃圾回收 + 磁盘保护 ---
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 3d";
  };
  nix.extraOptions = ''
    min-free = ${toString (512 * 1024 * 1024)}
    max-free = ${toString (2 * 1024 * 1024 * 1024)}
  '';

  # Nix 实验特性
  # Nix 设置
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # 并行构建加速（12核 CPU）
    max-jobs = "auto";
    cores = 0;
    auto-optimise-store = true;
    # 国内镜像 + 代理加速下载
    substituters = lib.mkForce [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
      "https://cosmic.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cosmic.cachix.org-1:Dya9IyXD4HwqkHRG02q1PEnwEKfPByjV+G3eTEfkwEo="
    ];
  };
  # 系统版本锁定
  system.stateVersion = "24.11";
}
