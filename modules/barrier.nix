{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    input-leap
  ];

  networking.firewall.allowedTCPPorts = [ 24800 ];
  networking.firewall.allowedUDPPorts = [ 24800 ];
}

