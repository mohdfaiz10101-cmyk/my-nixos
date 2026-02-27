{ config, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;
  services.flatpak.enable = true;
  environment.systemPackages = with pkgs; [
    flatpak
    input-remapper
  ];
  system.activationScripts.flatpak-repo = {
    text = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };
}