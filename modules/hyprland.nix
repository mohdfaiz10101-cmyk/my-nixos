{ config, pkgs, lib, ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  hardware.graphics.extraPackages = [ pkgs.egl-wayland ];

  environment.systemPackages = with pkgs; [
    egl-wayland
    waybar
    wofi
    mako
    libnotify
    wayvnc
    novnc
    python3Packages.websockify
    grim
    slurp
    wl-clipboard
    cliphist
    hyprpaper
    xfce.thunar
    brightnessctl
    pamixer
    swaylock
    swayidle
    xdg-desktop-portal-hyprland
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };

  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];

  programs.uwsm.waylandCompositors.hyprland = {
    prettyName = "Hyprland";
    comment = "Hyprland compositor managed by UWSM";
    binPath = "/run/current-system/sw/bin/Hyprland";
  };

  services.dbus.implementation = lib.mkForce "dbus";

  # Disable ALL display managers (SDDM, LightDM, etc.)
  # Use TTY autologin + .zprofile to start Hyprland
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;

  # TTY1 autologin for charlie, .zprofile will exec Hyprland
  services.getty.autologinUser = "charlie";

  # noGUI specialisation: Hyprland disabled via xserver disable in configuration.nix
}
