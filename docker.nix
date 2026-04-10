{ config, pkgs, ... }:

{
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/ai/docker";
      storage-driver = "overlay2";
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
  };
}
