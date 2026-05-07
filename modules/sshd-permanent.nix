{ config, pkgs, ... }: {
  services.openssh.enable = true;

  # sshd auto-restart if crashed (systemd native, no race conditions)
  systemd.services.sshd.serviceConfig = {
    Restart = "always";
    RestartSec = "10";
    StartLimitBurst = "5";
    StartLimitIntervalSec = "60";
  };
}
