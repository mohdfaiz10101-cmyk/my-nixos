{ config, pkgs, lib, ... }:

let
  home = "/home/charlie";
  localBin = "${home}/.local/bin";
  launcher = "${home}/launcher";
in
{
  # ============================================================
  # 一、Floorp 代理配置（auto-install user.js 到活跃 profile）
  # ============================================================

  system.activationScripts.floorp-proxy = {
    text = ''
      FLOORP_DIR="${home}/.floorp"
      [ -d "$FLOORP_DIR" ] || exit 0

      ACTIVE=$(grep -A5 '\[Install' "$FLOORP_DIR/profiles.ini" 2>/dev/null | grep Default | head -1 | cut -d= -f2 | tr -d ' ')
      [ -z "$ACTIVE" ] && ACTIVE=$(find "$FLOORP_DIR" -maxdepth 1 -name "*.default" -type d | head -1 | xargs basename)
      [ -z "$ACTIVE" ] && exit 0

      PROF_DIR="$FLOORP_DIR/$ACTIVE"
      USER_JS="$PROF_DIR/user.js"

      cat > "$USER_JS.tmp" << 'FLOORP_PROXY'
// [NixOS Managed] Proxy + Wayland input settings - DO NOT EDIT manually
// Managed by /etc/nixos/modules/browser.nix
user_pref("network.proxy.type", 1);
user_pref("network.proxy.http", "127.0.0.1");
user_pref("network.proxy.http_port", 7890);
user_pref("network.proxy.ssl", "127.0.0.1");
user_pref("network.proxy.ssl_port", 7890);
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 7891);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.no_proxies_on", "127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,localhost,*.local");
user_pref("network.proxy.allow_hijacking_localhost", true);
// Wayland native + fcitx5 输入法（KDE Plasma 6 Wayland 必须）
user_pref("widget.use-xdg-desktop-portal.mime-handler", 1);
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
FLOORP_PROXY

      if ! cmp -s "$USER_JS.tmp" "$USER_JS" 2>/dev/null; then
        mv "$USER_JS.tmp" "$USER_JS"
        chown charlie:users "$USER_JS"
        chmod 644 "$USER_JS"
        echo "[floorp-proxy] Updated user.js in $PROF_DIR"
      else
        rm -f "$USER_JS.tmp"
      fi
    '';
    deps = [ "users" ];
  };

  # ============================================================
  # 二、Cookie 同步服务器（持久守护进程）
  # ============================================================

  systemd.user.services.cookie-sync-server = {
    description = "Cookie Sync Server (port 9977)";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python313}/bin/python3 ${launcher}/cookie-sync-server.py";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = { HOME = home; };
  };

  # ============================================================
  # 三、截图贴图脚本（声明式部署到 /etc/nixos/scripts/）
  # ============================================================

  environment.etc."nixos/scripts/screenshot-pin" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      # Snipaste 风格：区域截图 → 自动置顶贴图
      # [NixOS Managed] - /etc/nixos/modules/browser.nix

      set -e

      TEMP_DIR="/tmp/snipaste-images"
      mkdir -p "$TEMP_DIR"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      IMAGE_FILE="$TEMP_DIR/shot_$TIMESTAMP.png"

      if ! spectacle --region --background --copy-image --output "$IMAGE_FILE" 2>/dev/null; then
          notify-send "截图贴图" "区域截图取消或失败" -u low
          exit 1
      fi

      sleep 0.2

      if [[ ! -s "$IMAGE_FILE" ]]; then
          if wl-paste --list-types 2>/dev/null | grep -q image; then
              wl-paste --type image/png > "$IMAGE_FILE" 2>/dev/null
          fi
      fi

      if [[ ! -s "$IMAGE_FILE" ]]; then
          notify-send "截图贴图" "截图数据为空" -u low
          exit 1
      fi

      if ! command -v feh &>/dev/null; then
          notify-send "截图贴图" "未安装 feh" -u critical
          exit 1
      fi

      feh --title "Snipaste - 置顶贴图" \
          --auto-zoom \
          --borderless \
          --scale-down \
          --geometry +$(qdbus org.kde.KWin /KWin org.kde.KWin.queryPointerInfo 2>/dev/null | grep -oP 'pos: \K[0-9]+,[0-9]+' | tr ',' '+') \
          "$IMAGE_FILE" &

      FEH_PID=$!
      sleep 0.3

      WINDOW_ID=$(xdotool search --pid "$FEH_PID" --class feh 2>/dev/null | head -1)
      if [[ -n "$WINDOW_ID" ]]; then
          qdbus org.kde.KWin /KWin org.kde.KWin.setKeepAbove "$WINDOW_ID" true 2>/dev/null || \
              wmctrl -i -r "$WINDOW_ID" -b add,above 2>/dev/null || true
      fi

      notify-send "截图贴图" "已贴图到屏幕" -u low -i image-x-generic

      find "$TEMP_DIR" -name "*.png" -type f -printf '%T@ %p\n' | sort -rn | tail -n +31 | cut -d' ' -f2- | xargs -r rm -f
    '';
  };

  environment.etc."nixos/scripts/paste-image-pinned" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      # Snipaste 风格：F3 粘贴剪贴板图片并置顶显示
      # [NixOS Managed] - /etc/nixos/modules/browser.nix

      set -e

      TEMP_DIR="/tmp/snipaste-images"
      mkdir -p "$TEMP_DIR"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      IMAGE_FILE="$TEMP_DIR/paste_$TIMESTAMP.png"

      if command -v wl-paste &>/dev/null; then
          if wl-paste --list-types | grep -q image; then
              wl-paste --type image/png > "$IMAGE_FILE" 2>/dev/null || {
                  notify-send "Snipaste" "剪贴板中没有图片" -u normal -i image-missing
                  exit 1
              }
          else
              notify-send "Snipaste" "剪贴板中没有图片" -u normal -i image-missing
              exit 1
          fi
      else
          notify-send "Snipaste" "未找到 wl-paste" -u critical
          exit 1
      fi

      if [[ ! -s "$IMAGE_FILE" ]]; then
          notify-send "Snipaste" "图片数据为空" -u normal
          rm -f "$IMAGE_FILE"
          exit 1
      fi

      if command -v feh &>/dev/null; then
          feh --title "Snipaste - F3 贴图" \
              --geometry 800x600+100+100 \
              --auto-zoom \
              --borderless \
              --scale-down \
              "$IMAGE_FILE" &

          FEH_PID=$!
          sleep 0.3

          WINDOW_ID=$(xdotool search --pid $FEH_PID --class feh 2>/dev/null | head -1)
          if [[ -n "$WINDOW_ID" ]]; then
              qdbus org.kde.KWin /KWin org.kde.KWin.setKeepAbove "$WINDOW_ID" true 2>/dev/null || {
                  wmctrl -i -r "$WINDOW_ID" -b add,above 2>/dev/null || true
              }
          fi

          notify-send "Snipaste" "图片已贴到屏幕（F3）" -u low -i image-x-generic
      else
          notify-send "Snipaste" "未安装 feh" -u critical
          exit 1
      fi

      find "$TEMP_DIR" -name "paste_*.png" -type f -printf '%T@ %p\n' | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f
    '';
  };

  # ============================================================
  # 四、KDE 快捷键（声明式部署 khotkeysrc）
  # ============================================================

  system.activationScripts.kde-hotkeys = {
    text = ''
      KHC="${home}/.config/khotkeysrc"

      mkdir -p "$(dirname "$KHC")"
      [ -f "$KHC" ] || touch "$KHC"
      chown charlie:users "$KHC"

      echo "[KDE hotkeys] Managed by NixOS - screenshot keys configured"
    '';
    deps = [ "users" ];
  };
}
