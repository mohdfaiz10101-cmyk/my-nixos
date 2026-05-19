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

    # OpenCode Sisy 公网访问（2026-05-16 新增）
    [[allowPorts]]
    start = 18090
    end = 18090

    # OpenCode × StepClaw 融合通道（2026-05-12 新增）
    [[allowPorts]]
    start = 19890
    end = 19890

    # OpenClaw Gateway + Letta MCP（2026-05-12 新增）
    [[allowPorts]]
    start = 19891
    end = 19893

    # KVM 桥接（ydotool-bridge）
    [[allowPorts]]
    start = 24801
    end = 24801

    # Windows FRP 端口（2026-05-18 新增）
    [[allowPorts]]
    start = 2222
    end = 2222

    [[allowPorts]]
    start = 3389
    end = 3389

    # CrewAI Gateway 公网访问（2026-05-18 新增）
    [[allowPorts]]
    start = 18091
    end = 18091

    # AGI Control Plane 公网访问（2026-05-18 新增）
    [[allowPorts]]
    start = 18300
    end = 18300

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
  networking.firewall.allowedTCPPorts = [ 7000 7500 2222 2223 2224 24801 3389 17699 18300 18090 18091 19890 19891 19892 19893 ];  # Win SSH 2222, NixOS SSH 2223, 手机 2224, KVM, RDP 3389
  networking.firewall.allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 ];  # mosh (NixOS + 手机)
}
