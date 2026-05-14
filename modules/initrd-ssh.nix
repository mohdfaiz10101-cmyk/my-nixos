{ config, pkgs, lib, ... }:

{
  # ========== initrd SSH — 系统崩溃时远程救援 ==========
  # 功能：GRUB 启动后 initrd 阶段即开启 SSH，可在系统完全启动前远程登录修复
  # 连接：ssh -p 2222 root@<ip>
  # 进入后：挂载 rootfs → chroot → nixos-rebuild switch 修复
  boot.initrd = {
    network = {
      enable = true;
      udhcpc.enable = true;
      ssh = {
        enable = true;
        port = 2222;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHAFruJJ+bY1fAh05xg86ZHMCh+dMJUq6GjmH11yq2uN charlie@nixos"
        ];
      };
    };
    systemd = {
      enable = true;
      # initrd 中可用的额外工具
      extraBin."nixos-enter" = "${pkgs.nixos-enter}/bin/nixos-enter";
    };
    # 必要的网络驱动（根据硬件调整）
    availableKernelModules = [ "r8169" "igc" "e1000e" "e1000" "tg3" "virtio_net" ];
  };

  # 确保密钥文件存在（sops-nix 管理或手动生成）
  system.activationScripts.initrdSshKeys = lib.mkAfter ''
    if [ ! -f /etc/secrets/initrd/ssh_host_ed25519_key ]; then
      mkdir -p /etc/secrets/initrd
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
      chmod 600 /etc/secrets/initrd/ssh_host_ed25519_key
      chmod 644 /etc/secrets/initrd/ssh_host_ed25519_key.pub
    fi
  '';
}
