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
    allowedTCPPorts = [
      22    # SSH
      # Docker 服务端口（iptables=false 后需手动开放）
      4000  # LiteLLM
      8283  # Letta proxy
      8284  # Letta API
      8000  # Dify/n8n
    ];
    # 仅允许局域网访问 Docker 服务，不对外暴露
    # 如需从外部访问，请在此添加具体 IP
    # 允许 Docker 容器（172.16/12 网段）访问宿主机代理端口 7890（mihomo）
    extraCommands = ''
      iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 7890 -j nixos-fw-accept
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
    };
    ports = [ 22 ];
  };
}
