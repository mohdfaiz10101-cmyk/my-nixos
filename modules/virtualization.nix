{ config, pkgs, lib, ... }:
{
  # --- Docker ---
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/ai/docker";
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

  # --- KVM / libvirt ---
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # --- Waydroid Android 容器 ---
  virtualisation.waydroid.enable = true;

  # --- Flatpak ---
  services.flatpak.enable = true;
}
