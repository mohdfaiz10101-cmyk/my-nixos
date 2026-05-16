{ config, pkgs, lib, ... }:
{
  # i3 WM (X11 — 规避 Wayland+NVIDIA 595.x D态挂死问题)
  services.xserver.windowManager.i3 = {
    enable = true;
    extraPackages = with pkgs; [ i3status i3lock dmenu ];
  };

  # 禁用 KDE/Plasma（不需要，节省资源）
  services.desktopManager.plasma6.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    rofi          # 应用启动器（替代 wofi）
    dunst         # 通知守护进程（替代 mako）
    libnotify
    feh           # 壁纸（替代 hyprpaper）
    maim          # 截图（替代 grim）
    xdotool
    xclip         # 剪贴板（替代 wl-clipboard）
    xss-lock      # 锁屏钩子
    picom         # 合成器（圆角/透明，可选）
    xfce.thunar   # 文件管理器
    brightnessctl
    pamixer
    x11vnc        # 远程桌面（替代 wayvnc）
    xterm         # 回退终端
  ];

  # XDG portal (X11)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };

  # fcitx5 在 X11 下必须显式设置（Wayland 下由 text-input-v3 自动处理，X11 不行）
  environment.sessionVariables = {
    GTK_IM_MODULE = lib.mkForce "fcitx";
    QT_IM_MODULE  = lib.mkForce "fcitx";
  };

  # 默认会话改为 i3
  services.displayManager.defaultSession = lib.mkForce "none+i3";

  # 禁用所有显示管理器，用 TTY autologin + startx
  services.displayManager.sddm.enable = lib.mkForce false;
  systemd.services.display-manager.enable = lib.mkForce false;

  # TTY1 自动登录
  services.getty.autologinUser = lib.mkForce "charlie";
}
