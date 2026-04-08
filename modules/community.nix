{ config, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;
  services.flatpak.enable = true;
  system.activationScripts.flatpak-repo = {
    text = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };
  # 注：flatpak, input-remapper 包已移至 modules/packages.nix
}
