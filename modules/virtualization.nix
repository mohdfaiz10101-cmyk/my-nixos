{ config, pkgs, lib, ... }:
{
  # === Docker 硬防护配置 ===
  # 防止 data-root 误指向 NTFS 分区，导致启动失败
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/ai/docker";  # ext4 loop mount (93G), 依赖 mnt-ai.mount
      # NVIDIA Container Runtime — 数字人流水线 GPU 直通
      runtimes.nvidia = {
        path = "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime";
        runtimeArgs = [];
      };
      # 让 NixOS 防火墙统一管理端口，Docker 不再自动操作 iptables
      # 需要手动在 networking.firewall 中开放 Docker 服务端口
      iptables = false;
      registry-mirrors = [];
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
    wants = [ "mnt-ai.mount" ];
  };

  # 注：/var/run 已由 NixOS 自动设为 /run 的符号链接，无需额外 tmpfiles 规则。
  # 旧版本 tmpfiles L+ 规则（已移除）会在 /var/run→/run 时创建 /run/docker.sock→/run/docker.sock 循环链接，
  # 导致 docker.socket 激活后 socket 文件丢失。

  # nvidia-container-runtime 配置文件（CDI 模式 + runc 绝对路径）
  # 重启后自动生成，防止 /etc/nvidia-container-runtime/config.toml 丢失
  environment.etc."nvidia-container-runtime/config.toml".text = ''
    disable-require = false
    supported-driver-capabilities = "compat32,compute,display,graphics,ngx,utility,video"

    [nvidia-container-cli]
    environment = []
    ldconfig = "@${pkgs.glibc.bin}/sbin/ldconfig"
    load-kmods = true

    [nvidia-container-runtime]
    log-level = "info"
    mode = "cdi"
    runtimes = ["${pkgs.runc}/bin/runc"]
  '';

  # --- KVM / libvirt ---
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # --- Waydroid Android 容器 ---
  virtualisation.waydroid.enable = true;

  # --- Flatpak ---
  services.flatpak.enable = true;
}
