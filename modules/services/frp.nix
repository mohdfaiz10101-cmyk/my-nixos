{ config, pkgs, lib, ... }:

# FRP Server (frps) — 内网穿透服务端
# 客户端连接: 192.168.2.100:7000 (局域网) / 公网IP:7000 (外网)

let
  frpsConfig = pkgs.writeText "frps.toml" ''
    bindPort = 7000
    # Dashboard
    webServer.addr = "0.0.0.0"
    webServer.port = 7500
    webServer.user = "admin"
    webServer.password = "frp@charlie2026"
    # Auth
    auth.method = "token"
    auth.token = "frp-token-charlie-2026"
    # Allow ports
    allowPorts = [
      { start = 17699, end = 17699 }
    ]
    # Logging
    log.to = "/var/log/frps/frps.log"
    log.level = "info"
    log.maxDays = 7
  '';
in
{
  # 创建日志目录
  systemd.tmpfiles.rules = [
    "d /var/log/frps 0755 root root -"
  ];

  systemd.services.frps = {
    description = "FRP Server (frps)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.frp}/bin/frps -c ${frpsConfig}";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 1048576;
    };
  };

  # 防火墙放行
  networking.firewall.allowedTCPPorts = [ 7000 7500 ];
}
