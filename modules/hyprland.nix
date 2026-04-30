{ config, pkgs, lib, ... }:
{
  # ── Hyprland Wayland 合成器 ──────────────────────────────────
  # 替代 KDE Plasma，保留 KDE 作 SDDM 回退选项
  # NVIDIA RTX 3060 Ti 专项配置，fcitx5 中文输入保留
  programs.hyprland = {
    enable = true;
    withUWSM = true;   # 统一会话管理，SDDM 注册为 "hyprland-uwsm"
    xwayland.enable = true;
  };

  # ── NVIDIA EGL-Wayland 桥接（Hyprland 必须，否则启动 1 秒崩溃）──
  hardware.graphics.extraPackages = [ pkgs.egl-wayland ];

  # ── 配套工具包 ───────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # NVIDIA EGL-Wayland 桥接（系统级安装确保 Wayland 合成器可用）
    egl-wayland
    # 状态栏
    waybar
    # 应用启动器
    wofi
    # 通知守护进程
    mako
    libnotify
    # 远程桌面 (7699 noVNC tab)
    wayvnc
    novnc
    python3Packages.websockify
    # 截图
    grim
    slurp
    # 剪贴板 (Wayland)
    wl-clipboard
    cliphist
    # 壁纸
    hyprpaper
    # 文件管理（无 KDE 环境）
    xfce.thunar
    # 亮度/音量控制
    brightnessctl
    pamixer
    # 锁屏
    swaylock
    # 空闲检测
    swayidle
    # XDG portal for Hyprland
    xdg-desktop-portal-hyprland
  ];

  # ── XDG Portal（截图/文件选择器）───────────────────────────
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };

  # home-manager useUserPackages 要求链接 xdg portal 定义
  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];

  # ── UWSM 托管 Hyprland（注册 hyprland-uwsm.desktop 到 SDDM）────
  # withUWSM=true 自动启用 programs.uwsm，但需要手动配置 waylandCompositors
  # 才能生成 session desktop 文件并注入 SDDM SessionDir
  programs.uwsm.waylandCompositors.hyprland = {
    prettyName = "Hyprland";
    comment = "Hyprland compositor managed by UWSM";
    binPath = "/run/current-system/sw/bin/Hyprland";
  };

  # 保持 dbus 不变（UWSM 默认改 broker，需重启，保留 dbus 避免 switch 失败）
  services.dbus.implementation = lib.mkForce "dbus";

  # ── 切换默认会话到 Hyprland，KDE 保留为回退 ─────────────────
  # 在 SDDM 登录界面可手动选择 "KDE Plasma" 回退
  # 禁用 NixOS 高层 autoLogin（防止它用 defaultSession 生成 plasma 自动登录）
  services.displayManager.autoLogin.enable = lib.mkForce false;
  services.displayManager.defaultSession = lib.mkForce "hyprland-uwsm";
  services.displayManager.sddm.settings.Autologin = lib.mkForce {
    Session = "hyprland-uwsm";
    User = "charlie";
    Relogin = true;
  };

  # ── noGUI specialisation 同步禁用 Hyprland ──────────────────
  # (noGUI 已在 configuration.nix 里禁用 xserver，Hyprland 随之失效，无需额外处理)
}
