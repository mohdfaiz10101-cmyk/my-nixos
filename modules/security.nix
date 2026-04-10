{ config, pkgs, lib, ... }:

{
  # PAM 进程数限制 - 防止 fork bomb
  # 背景：zsh fork bomb 事件（235 segfault/31秒，2290 进程/秒）
  # 参考：2026-04-09 系统防护加固
  security.pam.loginLimits = [
    { domain = "*"; type = "hard"; item = "nproc"; value = "4096"; }
    { domain = "*"; type = "soft"; item = "nproc"; value = "2048"; }
  ];

  # fail2ban — SSH 暴力破解防护（NixOS 内置 sshd jail）
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };
}
