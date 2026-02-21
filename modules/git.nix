{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    config = {
      alias = {
        st = "status";
        ad = "add .";
        up = "!git add . && git commit -m \"System Logic Update: $(date '+%Y-%m-%d %H:%M')\" && git push";
        last = "log -1 HEAD";
      };
      safe = {
        directory = "/etc/nixos";
      };
      core = {
        excludesfile = pkgs.writeText "git-global-ignore" ''
          hardware-configuration.nix
          secrets.nix
          user-secrets.nix
          result
          result-*
          *.swp
          .DS_Store
        '';
      };
    };
  };
}
