{ config, pkgs, lib, ... }:
{
  # === Docker 硬防护配置 ===
  # 防止 data-root 误指向 NTFS 分区，导致启动失败
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/var/lib/docker";  # ✓ EXT4 分区，由 NixOS 管理
      # 让 NixOS 防火墙统一管理端口，Docker 不再自动操作 iptables
      # 需要手动在 networking.firewall 中开放 Docker 服务端口
      iptables = false;
      registry-mirrors = [
        "https://docker.1ms.run"
        "https://docker.xuanyuan.me"
      ];
      proxies = {
        http-proxy = "http://127.0.0.1:7890";
        https-proxy = "http://127.0.0.1:7890";
        no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost,11434,18789";
      };
    };
  };

  # === systemd 集成：启动前路径验证 ===
  # Docker 启动时先运行检查脚本，确保 /var/lib/docker 可用且在 EXT4 上
  systemd.services.docker.preStart = ''
    /usr/bin/bash /etc/nixos/scripts/docker-path-verify.sh
  '';

  # --- KVM / libvirt ---
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # --- Waydroid Android 容器 ---
  virtualisation.waydroid.enable = true;

  # --- Flatpak ---
  services.flatpak.enable = true;
}
