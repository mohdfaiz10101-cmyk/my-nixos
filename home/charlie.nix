{ inputs, pkgs, lib, ... }:
{
  imports = [
    inputs.plasma-manager.homeModules.plasma-manager  # KDE 回退配置保留
  ];

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

  # ── Hyprland 窗口管理器配置 ──────────────────────────────────
  # NVIDIA RTX 3060 Ti 专项 env + fcitx5 + wayvnc + 7699 兼容
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      # NVIDIA 必须环境变量（Hyprland Wiki + NVIDIA 595 专项）
      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "XDG_SESSION_TYPE,wayland"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
        "__GL_GSYNC_ALLOWED,1"
        "__GL_VRR_ALLOWED,1"
        # fcitx5 中文输入
        "XMODIFIERS,@im=fcitx"
        "GTK_IM_MODULE,fcitx"
        "QT_IM_MODULE,fcitx"
        # Qt Wayland
        "QT_QPA_PLATFORM,wayland"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      ];

      # 显示器（自动检测）
      monitor = "HDMI-A-1,1920x1080@60,0x0,1.25";

      # 启动项
      exec-once = [
        "fcitx5 -d --replace"
        "waybar"
        "mako"
        "hyprpaper"
        "wl-paste --type text --watch cliphist store"
        "wayvnc 127.0.0.1 5900"
        "websockify 0.0.0.0:5998 127.0.0.1:5900"
        "input-leaps -f --config /home/charlie/.config/input-leap/input-leap.conf"
      ]

      # 修饰键
      "$mod" = "SUPER";

      # 基础快捷键
      bind = [
        "$mod, Return, exec, kitty"
        "$mod, Q, killactive"
        "$mod, F, fullscreen"
        "$mod, V, togglefloating"
        "$mod, Space, exec, wofi --show drun"
        "$mod SHIFT, Q, exit"
        "$mod, Tab, cyclenext"
        # 焦点移动（Vim 风格）
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"
        # 窗口大小调整
        "$mod CTRL, H, resizeactive, -20 0"
        "$mod CTRL, L, resizeactive, 20 0"
        "$mod CTRL, K, resizeactive, 0 -20"
        "$mod CTRL, J, resizeactive, 0 20"
        # 工作区切换 (1-6)
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        # 移动窗口到工作区
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        # 滚轮切换工作区
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
        # 截图
        ", Print, exec, grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png"
        "$mod, Print, exec, grim ~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png"
      ];

      # 鼠标绑定：SUPER+左键拖动，SUPER+右键调整大小
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # 窗口样式（Catppuccin Mocha 配色）
      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
        "col.active_border" = "rgba(89b4faee)";
        "col.inactive_border" = "rgba(313244aa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur = {
          enabled = true;
          size = 6;
          passes = 2;
        };
      };

      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 4, myBezier"
          "windowsOut, 1, 4, default, popin 80%"
          "fade, 1, 4, default"
          "workspaces, 1, 4, default"
        ];
      };

      # NVIDIA 硬件光标禁用（Hyprland 原生配置，双保险）
      # WLR_NO_HARDWARE_CURSORS env + cursor.no_hardware_cursors = true
      # NVIDIA DRM 不支持 hw cursors，不设置会导致合成器崩溃黑屏
      cursor = {
        no_hardware_cursors = true;
        inactive_timeout = 5;
        hide_on_key_press = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
        vfr = true;  # 可变帧率，NVIDIA 推荐
      };

      # 触控板
      input = {
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };
    };
  };

  # ── wayvnc 配置（允许无密码本地连接）─────────────────────────
  xdg.configFile."wayvnc/config".text = ''
    address=127.0.0.1
    enable_auth=false
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


  # ── Waybar  (Catppuccin Mocha) ─────────────────────────
  programs.waybar = {
    enable = true;
    style = ''
      @define-color base #1e1e2e;
      @define-color mantle #181825;
      @define-color crust #11111b;
      @define-color surface0 #313244;
      @define-color surface1 #45475a;
      @define-color surface2 #585b70;
      @define-color overlay0 #6c7086;
      @define-color text #cdd6f4;
      @define-color subtext0 #a6adc8;
      @define-color blue #89b4fa;
      @define-color green #a6e3a1;
      @define-color red #f38ba8;
      @define-color yellow #f9e2af;
      @define-color peach #fab387;
      @define-color mauve #cba6f7;
      @define-color teal #94e2d5;
      @define-color lavender #b4befe;

      * {
        font-family: "Hack Nerd Font", "Noto Sans CJK SC";
        font-size: 13px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      window#waybar {
        background: @base;
        color: @text;
      }

      window#waybar.hidden { opacity: 0.2; }

      #workspaces button {
        padding: 0 10px;
        background: transparent;
        color: @text;
        border-bottom: 2px solid transparent;
      }
      #workspaces button.focused { border-bottom: 2px solid @blue; color: @blue; }
      #workspaces button.urgent { border-bottom: 2px solid @red; color: @red; }
      #workspaces button:hover { background: @surface0; }

      tooltip { background: @mantle; color: @text; border: 1px solid @surface0; }
      tooltip label { color: @text; }

      #mode, #window { padding: 0 10px; color: @text; }
      #window.focused { color: @blue; }

      #clock { color: @blue; padding: 0 10px; }
      #battery { padding: 0 10px; color: @green; }
      #battery.warning { color: @peach; }
      #battery.critical { color: @red; }
      #cpu { padding: 0 10px; color: @green; }
      #memory { padding: 0 10px; color: @mauve; }
      #temperature { padding: 0 10px; color: @teal; }
      #network { padding: 0 10px; color: @text; }
      #network.disconnected { color: @overlay0; }
      #pulseaudio { padding: 0 10px; color: @lavender; }
      #pulseaudio.muted { color: @overlay0; }
      #backlight { padding: 0 10px; color: @yellow; }
      #tray { padding: 0 10px; }
      #tray > .passive { color: @subtext0; }
      #tray > .needs-attention { color: @red; }
      #custom-date { padding: 0 10px; color: @mauve; }
      #idle_inhibitor { padding: 0 10px; color: @yellow; }
      #idle_inhibitor.activated { color: @red; }
    '';

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 28;
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "hyprland/window" ];
        modules-right = [ "tray" "idle_inhibitor" "network" "pulseaudio" "cpu" "memory" "battery" "clock" ];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
          format-icons = {
            default = "○";
            focused = "●";
            urgent = "!";
            "1" = "一";
            "2" = "二";
            "3" = "三";
            "4" = "四";
            "5" = "五";
            "6" = "六";
          };
        };

        "hyprland/window" = {
          format = "{}";
          max-length = 50;
        };

        clock = {
          format = " {:%H:%M}";
          format-alt = " {:%Y-%m-%d %H:%M}";
        };

        cpu = { format = " {usage}%"; };
        memory = { format = "󰍛 {}%"; };

        network = {
          format-wifi = " {essid}";
          format-ethernet = " {ipaddr}";
          format-disconnected = "󰤭 断开";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-bluetooth = " {volume}%";
          format-muted = "󰖁 静音";
          format-icons = { default = [ "󰕿" "󰖀" "󰕾" ]; };
          on-click = "pamixer -t";
        };

        battery = {
          states = { warning = 30; critical = 15; };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰂀" ];
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons.activated = "󰅶";
          format-icons.deactivated = "󰾪";
        };

        tray = { spacing = 8; };
      };
    };
  };

  # ── Caddy Launcher Gateway (:7699) — 手机统一入口 ──
  # 修复历史：After=network.target 在用户级 systemd 无效，导致开机后 /mnt/ai
  # 未挂载时 caddy 启动失败。改为 After/Wants mnt-ai.mount 确保挂载后再启动。
  systemd.user.services.caddy-launcher = {
    Unit = {
      Description = "Caddy Launcher Gateway (:7699)";
      After = [ "mnt-ai.mount" ];
      Wants = [ "mnt-ai.mount" ];
    };
    Service = {
      ExecStart = "%h/.nix-profile/bin/caddy run --config /mnt/ai/apps/launcher/Caddyfile";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 10;
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

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
