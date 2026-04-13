{ config, pkgs, lib, ... }:

{
  # LiteLLM 健康检查 + 自动拉起服务
  # 每 5 分钟检查一次，不健康则自动重启

  systemd.services.litellm-healthcheck = {
    description = "LiteLLM Health Check and Auto-Restart";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/litellm-healthcheck.sh";
      User = "root";  # 需要 systemctl 权限
    };
  };

  systemd.timers.litellm-healthcheck = {
    description = "LiteLLM Health Check Timer (every 5 minutes)";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2min";       # 启动 2 分钟后首次检查
      OnUnitActiveSec = "5min"; # 每 5 分钟检查一次
      Unit = "litellm-healthcheck.service";
    };
  };

  # 确保日志目录存在
  systemd.tmpfiles.rules = [
    "f /var/log/litellm-healthcheck.log 0644 root root -"
  ];
}
