{ config, pkgs, lib, ... }:

# FRP Server (frps) — 内网穿透服务端
# 客户端连接: 192.168.2.100:7000 (局域网) / 公网IP:7000 (外网)

let
  frpsConfig = pkgs.writeText "frps.toml" ''
    bindPort = 7000

    [webServer]
    addr = "0.0.0.0"
    port = 7500
    user = "admin"
    password = "frp@charlie2026"

    [auth]
    method = "token"
    token = "frp-token-charlie-2026"

    # NixOS 端口
    [[allowPorts]]
    start = 2223
    end = 2223

    [[allowPorts]]
    start = 17699
    end = 17699

    [[allowPorts]]
    start = 60000
    end = 60002

    # 手机端口
    [[allowPorts]]
    start = 2224
    end = 2224

    [[allowPorts]]
    start = 60003
    end = 60005

    # OpenCode × StepClaw 融合通道（2026-05-12 新增）
    [[allowPorts]]
    start = 19890
    end = 19890

    # OpenClaw Gateway（2026-05-12 新增）
    [[allowPorts]]
    start = 19892
    end = 19893

    [log]
    to = "/var/log/frps/frps.log"
    level = "info"
    maxDays = 7
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
  networking.firewall.allowedTCPPorts = [ 7000 7500 2224 ];  # 添加手机 SSH 端口
  networking.firewall.allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 ];  # mosh (NixOS + 手机)
}
