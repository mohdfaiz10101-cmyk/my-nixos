{ config, pkgs, lib, ... }:

{
  # PAM 进程数限制 - 防止 fork bomb
  # 背景：zsh fork bomb 事件（235 segfault/31秒，2290 进程/秒）
  # 参考：2026-04-09 系统防护加固
  security.pam.loginLimits = [
    { domain = "*"; type = "hard"; item = "nproc"; value = "4096"; }
    { domain = "*"; type = "soft"; item = "nproc"; value = "2048"; }
  ];

  # Coredump 限制 — 防止堆积占满磁盘（曾堆积 4.1GB）
  systemd.coredump = {
    enable = true;
    extraConfig = ''
      Storage=external
      Compress=yes
      ProcessSizeMax=256M
      MaxFileAge=7day
      MaxUse=1G
    '';
  };

  # fail2ban — SSH 暴力破解防护（NixOS 内置 sshd jail）
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };
}
