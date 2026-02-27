{ config, pkgs, lib, ... }:
let
  proxyWatchdog = pkgs.writeShellScriptBin "proxy-watchdog" ''
    MAIN_PORT="7890"
    CHECK_URL="https://www.google.com"
    while true; do
      if ${pkgs.curl}/bin/curl -o /dev/null -s -m 5 --proxy http://127.0.0.1:$MAIN_PORT $CHECK_URL; then
        if systemctl is-active --quiet dae.service; then
          echo "[Watchdog] Mihomo OK. Stopping dae..."
          systemctl stop dae.service
        fi
      else
        if ! ${pkgs.curl}/bin/curl -o /dev/null -s -m 5 $CHECK_URL; then
          echo "[Watchdog] Connection lost. Starting dae..."
          systemctl start dae.service
        fi
      fi
      sleep 30
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    mihomo
    clash-verge-rev
    daed
    proxyWatchdog
  ];

  services.dae = {
    enable = true;
    config = "global { lan_interface: auto; wan_interface: auto } routing {}";
  };
  systemd.services.dae.wantedBy = lib.mkForce [];

  systemd.services.proxy-watchdog = {
    description = "Proxy Auto-Switch Watchdog";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${proxyWatchdog}/bin/proxy-watchdog";
      Restart = "always";
      User = "root";
    };
  };
}