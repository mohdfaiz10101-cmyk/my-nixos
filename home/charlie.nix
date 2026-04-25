{ inputs, pkgs, lib, ... }:
{
  imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

  home.username = "charlie";
  home.homeDirectory = "/home/charlie";
  home.stateVersion = "25.05";

  # ── mpv 媒体播放器 ──
  programs.mpv.enable = true;

  # ── Kitty 终端：声明式固化中文输入配置 ──
  programs.kitty = {
    enable = true;
    settings = {
      font_size = 13.0;
      scrollback_lines = 10000;
      cursor_shape = "beam";
      cursor_blink_interval = 0.5;
      remember_window_size = "yes";
      window_padding_width = 4;
      wayland_enable_ime = "yes";
      input_method = "fcitx5";
      allow_hyperlinks = "yes";
    };
    keybindings = {
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      "ctrl+shift+equal" = "change_font_size all +2.0";
      "ctrl+shift+minus" = "change_font_size all -2.0";
      "ctrl+shift+0" = "change_font_size all 0";
    };
    extraConfig = ''
      # 触控板/鼠标滚轮缩放字体
      map ctrl+scroll_up change_font_size all +1.0
      map ctrl+scroll_down change_font_size all -1.0

      # 滚动
      mouse_map shift+scroll_up scroll_page_up
      mouse_map shift+scroll_down scroll_page_down
    '';
  };

  # ── KDE Plasma 任务栏声明式固化 ──────────────────────────────
  # 防止每次开机/rebuild 后任务栏丢失，固定 launchers 使用 applications: 协议
  # 避免 /nix/store/xxx 硬编码路径（rebuild 后路径变更导致图标消失）
  programs.plasma = {
    enable = true;

    panels = [
      {
        location = "bottom";
        height = 44;
        widgets = [
          "org.kde.plasma.kickoff"
          {
            name = "org.kde.plasma.icontasks";
            config.General = {
              launchers = builtins.concatStringsSep "," [
                "applications:org.kde.konsole.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:floorp.desktop"
                "applications:org.remmina.Remmina.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:obsidian.desktop"
              ];
              iconSize = "3";
              iconSpacing = "1";
            };
          }
          "org.kde.plasma.marginsseparator"
          {
            name = "org.kde.plasma.systemtray";
            config.General = {
              extraItems = builtins.concatStringsSep "," [
                "org.kde.plasma.clipboard"
                "org.kde.plasma.manage-inputmethod"
                "org.kde.plasma.devicenotifier"
                "org.kde.plasma.notifications"
                "org.kde.plasma.volume"
                "org.kde.plasma.networkmanagement"
                "org.kde.plasma.keyboardlayout"
                "org.kde.kscreen"
                "org.kde.plasma.brightness"
                "org.kde.plasma.battery"
                "org.kde.plasma.mediacontroller"
              ];
            };
          }
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
  };

  # ── 修复 ~/.cache 符号链接导致 home-manager 启动失败 ──
  # 根因：~/.cache 是指向 /mnt/ai/cache/xdg 的符号链接
  # HM linkGeneration 尝试 mkdir ~/.cache → 报"文件已存在" → 级联失败
  # 方案：在 linkGeneration 前清理旧的 .keep 符号链接，让 HM 重新创建
  home.activation.fixCacheKeep = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    if [ -L "$HOME/.cache/.keep" ]; then
      $DRY_RUN_CMD rm -f "$HOME/.cache/.keep"
    fi
  '';

  # ── xdg-desktop-portal 提前启动（防止 Plasma 组件 DBus NoReply 超时卡死）──
  # 根因：portal 默认懒启动，Plasma 各组件启动时 portal 未就绪
  # → "Failed to register with host portal QDBusError NoReply" → 会话看似卡死
  # 方案：在 graphical-session.target.wants/ 添加 portal 链接，使其随会话启动
  home.activation.enableXdgPortalEager = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WANTS_DIR="$HOME/.config/systemd/user/graphical-session.target.wants"
    PORTAL_SVC="/etc/systemd/user/xdg-desktop-portal.service"
    if [ ! -L "$WANTS_DIR/xdg-desktop-portal.service" ] && [ -f "$PORTAL_SVC" ]; then
      $DRY_RUN_CMD mkdir -p "$WANTS_DIR"
      $DRY_RUN_CMD ln -sf "$PORTAL_SVC" "$WANTS_DIR/xdg-desktop-portal.service"
    fi
  '';

  # ── Floorp 声明式 desktop entry：强制走 wrapper（修复输入法）──
  # wrapper 在 ~/.local/bin/floorp，设置 MOZ_ENABLE_WAYLAND=1 + unset IM 变量
  xdg.desktopEntries.floorp = {
    name = "Floorp";
    exec = "/home/charlie/.local/bin/floorp %U";
    icon = "floorp";
    comment = "Browse the Web";
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "text/xml" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" ];
    settings = {
      StartupWMClass = "floorp";
    };
  };
}
