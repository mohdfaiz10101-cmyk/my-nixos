{ config, pkgs, inputs, lib, ... }:

# ============================================================
# 统一包管理模块
#
# 所有 environment.systemPackages 集中在此文件管理。
# 各功能模块只保留服务定义和非包配置。
# 分类：系统 -> 桌面 -> 开发 -> 浏览器 -> 通讯 -> AI -> 磁盘 -> 主题
# ============================================================

let
  # 生产力工具 voxtype（本地构建）
  voxtype = pkgs.stdenv.mkDerivation rec {
    pname = "voxtype";
    version = "0.6.5";
    src = pkgs.fetchurl {
      url = "https://github.com/peteonrails/voxtype/releases/download/v${version}/voxtype-${version}-linux-x86_64-avx2";
      sha256 = "sha256-28QTFbkrLOyDioCwr9G77muSCssXvgUcSDg9k2eP+CQ=";
    };
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = with pkgs; [ autoPatchelfHook ];
    buildInputs = with pkgs; [
      alsa-lib stdenv.cc.cc.lib
      xorg.libX11 xorg.libXext xorg.libXrandr libGL
    ];
    installPhase = ''
      runHook preInstall
      install -D $src $out/bin/voxtype
      chmod +x $out/bin/voxtype
      runHook postInstall
    '';
    meta = with lib; {
      description = "Voice-to-text with push-to-talk for Wayland";
      homepage = "https://voxtype.io";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };

  # 三机位垂直对齐脚本
  scrcpy-layout = pkgs.writeShellScriptBin "scrcpy-layout" ''
    DEVICES=($(${pkgs.android-tools}/bin/adb devices | grep -v "List" | awk '{print $1}'))
    for i in "''${!DEVICES[@]}"; do
      OFFSET=$((i * 450))
      ${pkgs.scrcpy}/bin/scrcpy -s "''${DEVICES[$i]}" \
        --window-title "Phone_$i" \
        --window-x $OFFSET --window-y 100 \
        --window-width 400 --always-on-top &
    done
  '';

  # 一键同步维护脚本
  nx-apply = pkgs.writeShellScriptBin "nx-apply" ''
    cd /etc/nixos
    sudo chown -R charlie:users .
    git add .
    sudo nixos-rebuild switch --flake .#charlie --impure
  '';
in
{
  environment.systemPackages = with pkgs; [
    # === 系统工具 ===
    wget
    curl
    git
    vim
    htop
    fastfetch
    ntfs3g
    jq
    yq-go
    rclone
    inotify-tools
    restic
    wl-clipboard
    translate-shell
    pciutils
    usbutils
    sshpass
    numlockx

    # OCR（多语言）
    (tesseract5.override { enableLanguages = [ "eng" "chi_sim" "chi_tra" "jpn" "kor" ]; })

    # 文档处理
    pandoc
    hunspell
    hunspellDicts.en_US
    sqlcipher
    recoll  # 全文索引（闲置时自动更新）
    # texlive 临时禁用 — 磁盘空间不足（两阶段重建 Phase 1）
    # (texlive.combine {
    #   inherit (texlive)
    #     scheme-small collection-langchinese collection-fontsrecommended
    #     fancyhdr titlesec geometry enumitem xcolor hyperref bookmark;
    # })

    # === 桌面工具 ===
    feh
    xdotool
    wmctrl
    imagemagick
    zenity
    appimage-run
    ulauncher
    mergerfs
    mergerfs-tools
    snapraid
    e2fsprogs
    parted

    # === 开发工具 ===
    nodejs_22
    python313
    python313Packages.anthropic
    python313Packages.requests
    docker-compose
    direnv
    vscode-with-extensions
    # jetbrains.idea  # 临时禁用 — 磁盘空间不足（两阶段重建 Phase 1）
    claude-code
    cursor-cli
    code-cursor-fhs
    zed-editor
    windsurf

    # === 浏览器 ===
    firefox
    inputs.zen-browser.packages.x86_64-linux.default
    floorp-bin
    google-chrome

    # === 通讯 ===
    wechat-uos
    telegram-desktop

    # === 远程桌面 & 投屏 ===
    remmina
    moonlight-qt
    rustdesk-flutter
    kdePackages.krfb
    scrcpy
    android-tools

    # === 网络 & 代理 ===
    flclash
    xray
    mihomo

    # === AI & 语音 ===
#    ollama-cuda  # 临时禁用：磁盘空间不足
    whisper-cpp
    ffmpeg
    sox
    voxtype
    wtype
    ydotool
    pulseaudio
    libnotify

    # === 终端 ===
    ghostty
    wezterm
    warp-terminal
    kitty
    zellij
    starship        # 智能提示符
    atuin           # 命令历史搜索
    fzf             # 模糊查找

    # === KDE 桌面增强 ===
    catppuccin-cursors.mochaDark
    catppuccin-kde
    catppuccin-kvantum
    catppuccin-gtk
    kdePackages.qtstyleplugin-kvantum
    tela-icon-theme
    tela-circle-icon-theme
    papirus-icon-theme
    kdePackages.discover
    packagekit
    input-remapper

    # === Spectacle OCR 翻译 ===
    (kdePackages.spectacle.override {
      tesseractLanguages = [ "eng" "chi_sim" "chi_tra" "jpn" "kor" ];
    })

    # === 办公 & 字体 ===
    libreoffice-qt6-fresh
    keepassxc
    noto-fonts
    noto-fonts-cjk-serif
    noto-fonts-cjk-sans
    noto-fonts-color-emoji

    # === Flatpak ===
    flatpak

    # === 网络工具 ===
    tailscale
    ttyd

    # === 浏览器自动化 & 图片 ===
    # playwright-mcp  # 临时禁用 — 磁盘空间不足（两阶段重建 Phase 1）
    imv

    # === 自定义脚本包 ===
    scrcpy-layout
    nx-apply
  ] ++ (let
    # uTools 可选包（可能不存在于 nixpkgs）
    checkPkg = name: if builtins.hasAttr name pkgs then [ pkgs.${name} ] else [];
  in (checkPkg "uTools") ++ (checkPkg "utools"));
}
