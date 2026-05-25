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

    # ttyd 终端（2026-05-23 从 17699 迁移到 17698）
    [[allowPorts]]
    start = 17698
    end = 17698

    [[allowPorts]]
    start = 17699
    end = 17699

    [[allowPorts]]
    start = 17700
    end = 17700

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

    # 手机 ADB FRP 隧道（2026-05-21 新增）
    [[allowPorts]]
    start = 15555
    end = 15555

    # 手机 SSH FRP 隧道（2026-05-21 新增）
    [[allowPorts]]
    start = 8022
    end = 8022

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

    # AGI Control Plane 直连 3000（2026-05-25 新增）
    [[allowPorts]]
    start = 3000
    end = 3000

    # Khoj 知识库 42111（2026-05-25 新增）
    [[allowPorts]]
    start = 42111
    end = 42111

    # OpenAgents WebSocket 端口（18092 被 macg_mcp.py 占用，改 18093）
    [[allowPorts]]
    start = 18093
    end = 18093

    # OpenAgents Network 公网访问（2026-05-23 新增）
    [[allowPorts]]
    start = 18700
    end = 18700

    # Sunshine/Moonlight 远程串流（2026-05-23 新增）
    [[allowPorts]]
    start = 47980
    end = 47980

    [[allowPorts]]
    start = 47994
    end = 47994

    [[allowPorts]]
    start = 47999
    end = 47999

    [[allowPorts]]
    start = 48020
    end = 48020

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
      ExecStart = "/usr/local/bin/frps -c ${frpsConfig}";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 1048576;
      # 内存上限：frp 正常 <100MB，超过 400MB 说明异常，OOM killer 主动介入
      MemoryMax = "400M";
      MemoryHigh = "300M";
      # 崩溃重启限制：10分钟内最多5次
      StartLimitIntervalSec = 600;
      StartLimitBurst = 5;
    };
  };

  # 防火墙放行
   networking.firewall.allowedTCPPorts = [ 7000 7500 2222 2223 2224 24801 3389 17698 17699 17700 15555 8022 18300 18090 18091 18092 18093 18700 19890 19891 19892 19893 47984 47989 47990 48010 42110 3000 ];  # Win SSH 2222, NixOS SSH 2223, 手机 2224, 手机ADB 15555, 手机SSH 8022, KVM, RDP 3389, ttyd 17698, Launcher 17699, ttyd 17700, OpenAgents 18092, OpenAgents Network 18700
  networking.firewall.allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 ];  # mosh (NixOS + 手机)
}
