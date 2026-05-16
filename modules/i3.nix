{ config, pkgs, lib, ... }:
{
  services.xserver.windowManager.i3 = {
    enable = true;
    extraPackages = with pkgs; [ i3status i3lock dmenu ];
  };

  services.desktopManager.plasma6.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    rofi
    dunst
    libnotify
    picom
    feh
    maim
    flameshot
    xclip
    xfce.thunar
    pamixer
    pavucontrol
    playerctl
    pulseaudio
    networkmanagerapplet
    xfce.xfce4-power-manager
    xss-lock
    arandr
    lxappearance
    xdotool
    brightnessctl
    x11vnc
    xterm
  ];

  networking.networkmanager.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };

  environment.sessionVariables = {
    GTK_IM_MODULE = lib.mkForce "fcitx";
    QT_IM_MODULE  = lib.mkForce "fcitx";
  };

  services.displayManager.defaultSession = lib.mkForce "none+i3";

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = false;
  services.displayManager.autoLogin = {
    enable = true;
    user = "charlie";
  };
  services.displayManager.sddm.settings.Autologin = {
    Session = "none+i3";
    User = "charlie";
    Relogin = false;
  };

  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
}
