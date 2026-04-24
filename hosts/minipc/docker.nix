{ config, pkgs, lib, ... }:
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    daemon.settings = {
      data-root = "/var/lib/docker";  # 本地 NVMe，不需要 /mnt/ai
      iptables = false;  # NixOS 防火墙统一管理端口
      registry-mirrors = [
        "https://docker.1ms.run"
        "https://docker.xuanyuan.me"
      ];
      proxies = {
        http-proxy = "http://192.168.2.100:7890";  # 走大主机代理
        https-proxy = "http://192.168.2.100:7890";
        no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost,.bigmodel.cn,.siliconflow.cn";
      };
    };
  };

  # 防火墙开放常用服务端口
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    4000  # LiteLLM
    8283  # Letta API
    8284  # Letta UI
    8000  # ChromaDB
    3001  # Twenty CRM
    5678  # n8n
    8080  # OpenCode
    9876  # CRM Agent
    3010  # Langfuse
    5244  # Alist
  ];

  # 实用工具
  environment.systemPackages = with pkgs; [
    docker-compose
    docker
    python3
    git
    curl
    wget
    htop
    vim
    jq
    rsync
  ];

  # charlie 加入 docker 组
  users.users.charlie.extraGroups = lib.mkMerge [
    (lib.mkBefore [ "docker" ])
  ];
}
