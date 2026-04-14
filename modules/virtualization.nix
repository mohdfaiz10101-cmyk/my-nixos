{ config, pkgs, lib, ... }:
{
  # === Docker 硬防护配置 ===
  # 防止 data-root 误指向 NTFS 分区，导致启动失败
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/ai/docker";  # ext4 loop mount (93G), 依赖 mnt-ai.mount
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
        # 国内服务直连（不走代理）：
        # - 127/192 内网
        # - *.bigmodel.cn (GLM)
        # - *.siliconflow.cn (DeepSeek/Qwen)
        # - localhost Ollama/其他本地服务
        no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost,.bigmodel.cn,.siliconflow.cn,api.siliconflow.cn,open.bigmodel.cn,11434,18789";
      };
    };
  };

  # === systemd 集成：Docker 依赖 ext4 loop mount ===
  systemd.services.docker = {
    after = [ "mnt-ai.mount" ];
    requires = [ "mnt-ai.mount" ];
  };

  # Docker CLI 默认查找 /var/run/docker.sock，但实际 socket 在 /run/docker.sock
  # /var/run 不是 /run 的符号链接，且权限 0700 阻止非 root 遍历
  # 修复：放宽 /var/run 权限 + 创建符号链接
  systemd.tmpfiles.rules = [
    "d /var/run 0755 root root -"
    "L+ /var/run/docker.sock - - - - /run/docker.sock"
  ];

  # --- KVM / libvirt ---
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # --- Waydroid Android 容器 ---
  virtualisation.waydroid.enable = true;

  # --- Flatpak ---
  services.flatpak.enable = true;
}
