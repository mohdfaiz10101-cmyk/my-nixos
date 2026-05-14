{ config, pkgs, lib, ... }:

{
  # ========== OpenCode Recovery Mode — GRUB 一键 AI 急救 ==========
  # 功能：GRUB 菜单新增 "OpenCode Recovery" 选项
  #       启动到最小 TTY → 自动登录 charlie → 拉起 opencode → AI 诊断修复
  # 使用：开机 GRUB 选 "NixOS — OpenCode Recovery" 进入

  # 添加 GRUB 菜单项
  boot.loader.grub.extraEntries = lib.mkOrder 10 ''
    menuentry "NixOS — OpenCode Recovery (AI Rescue)" {
      search --set=root --label nixos
      linux /boot/bzImage nomodeset systemd.unit=multi-user.target opencode_recovery=1 console=tty1
      initrd /boot/initrd
    }
  '';

  # 检测 opencode_recovery=1 内核参数 → 启动 recovery 服务
  systemd.services.opencode-recovery = {
    description = "OpenCode AI Recovery Mode — Auto-launch opencode on TTY1";
    # 在 multi-user.target 之后启动，确保网络就绪
    after = [ "multi-user.target" "network-online.target" ];
    # 只在 opencode_recovery=1 内核参数时启动
    conditionKernelCommandLine = "opencode_recovery=1";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      # 等待网络就绪后启动 opencode
      ExecStartPre = "${pkgs.systemd}/bin/systemctl is-system-running --wait";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/opencode-recovery.sh";
      User = "charlie";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
    };
  };

  # 确保 opencode 在 PATH 中
  environment.systemPackages = with pkgs; [ nodejs ];
  environment.variables.PATH = lib.mkForce [
    "/home/charlie/.npm-global/bin"
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/home/charlie/.nix-profile/bin"
    "/usr/bin"
    "/bin"
  ];
}
