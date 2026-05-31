{ config, pkgs, lib, ... }:

{
  # LiteLLM 健康检查已并入 health-aggregator。
  # 保留手动 service，不再启用 timer，避免多个健康检查同时重启/告警。

  systemd.services.litellm-healthcheck = {
    description = "LiteLLM Health Check and Auto-Restart";
    path = with pkgs; [ docker docker-compose curl bash systemd ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/litellm-healthcheck.sh";
      User = "root";  # 需要 systemctl 权限
    };
  };

  systemd.timers.litellm-healthcheck = {
    description = "LiteLLM Health Check Timer (every 5 minutes)";
    wantedBy = lib.mkForce [];

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
