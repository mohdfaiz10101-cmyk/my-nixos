{ config, pkgs, lib, ... }:
{
  # --- 基本网络 ---
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # 备用 DNS — Tailscale DNS 失败时自动降级
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" "223.5.5.5" ];

  # NetworkManager-wait-online 默认等待所有接口就绪（耗时 6.5s），禁用
  systemd.services.NetworkManager-wait-online.enable = false;

  # LAN 固定设备名称解析
  networking.extraHosts = ''
    192.168.2.100 tony nixos
    192.168.2.101 minipc
    192.168.2.36  winpc windows
  '';

  # --- 防火墙 ---
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" "wlp0s20f0u5" ];  # Tailscale 已端对端加密，WiFi LAN 信任全部流量（minipc 代理访问）
    allowedTCPPorts = [
      22    # SSH
      # Docker 服务端口（iptables=false 后需手动开放）
      4000  # LiteLLM
      8283  # Letta proxy
      8284  # Letta API
      8000  # Dify/n8n
      7699  # AI Launcher（手机统一入口，Caddy reverse proxy）
      7690  # ttyd Claude Code
    ];
    # 仅允许局域网访问 Docker 服务，不对外暴露
    # 如需从外部访问，请在此添加具体 IP
    # 允许 Docker 容器（172.16/12 网段）访问宿主机代理端口 7890（mihomo）
    # Docker 容器网段动态访问宿主机端口（替代 docker-iptables-allow.service 手动脚本）
    extraCommands = ''
      # Tailscale 对端 IP (100.64.0.0/10) 被 ts-input rule3 DROP，trustedInterfaces 在 nixos-fw 中太晚
      # 在 INPUT 最前插入 tailscale0 接口放行，确保跑在 ts-input 之前
      iptables -I INPUT 1 -i tailscale0 -j ACCEPT
      # Docker 容器访问宿主机代理
      iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 7890 -j nixos-fw-accept
      iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 7891 -j nixos-fw-accept
      iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 11434 -j nixos-fw-accept
      # LAN 设备（minipc 等）访问宿主机代理
      iptables -A nixos-fw -s 192.168.2.0/24 -p tcp --dport 7890 -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D INPUT -i tailscale0 -j ACCEPT 2>/dev/null || true
    '';
  };

  # --- SSH 服务（Vast.ai GPU 出租必需）---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      X11Forwarding = false;
      AllowTcpForwarding = "yes";
      GatewayPorts = "clientspecified";
    };
    ports = [ 22 ];
  };
}
