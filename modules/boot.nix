{ config, pkgs, lib, ... }:
{
  # --- zram 壓縮 Swap（內存不足 16G 時的安全網）---
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;  # 23GB RAM × 25% ≈ 5.8GB swap（之前50%过多）
  };

  # --- 降低 swappiness（优先用 RAM，zramSwap 作为安全网）---
  boot.kernel.sysctl."vm.swappiness" = 10;

  # --- GRUB 引导器（双系统 + Windows EFI fix）---
  boot.loader = {
    efi.canTouchEfiVariables = false;
    efi.efiSysMountPoint = "/boot/efi";
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "nodev";
      useOSProber = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 5;
      theme = pkgs.sleek-grub-theme;
      gfxmodeEfi = "1920x1080";
      extraEntries = lib.mkOrder 0 ''
        menuentry "Windows 11 (Physical NVMe Fix)" {
          insmod part_gpt
          insmod fat
          insmod search_fs_uuid
          insmod chain
          search --fs-uuid --set=root FA67-631E
          chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        }
      '';
    };
  };

  # --- GRUB → EFI 分区同步（永久修复）---
  # bootPath=/boot 在 rootfs ext4，GRUB EFI 二进制从 /boot/efi (FAT32) 读 grub.cfg
  # switch-to-configuration 先写 GRUB 再跑 activation，所以这里能拿到最新的 grub.cfg
  # boot 模式下也同步：在 GRUB 安装脚本后立刻 sync
  boot.loader.grub.extraInstallCommands = ''
    if [ -f /boot/grub/grub.cfg ] && [ -d /boot/efi/grub ]; then
      ${pkgs.coreutils}/bin/cp /boot/grub/grub.cfg /boot/efi/grub/grub.cfg
    fi
  '';
  system.activationScripts.syncGrubToEfi = lib.mkAfter ''
    if [ -f /boot/grub/grub.cfg ] && [ -d /boot/efi/grub ]; then
      cp /boot/grub/grub.cfg /boot/efi/grub/grub.cfg
    fi
  '';

  # NVIDIA Wayland 黑屏修复：启用 NVIDIA framebuffer device，KDE Plasma 6 Wayland 必需
  # 症状：KDE 开机黑屏，程序可以运行但无桌面壳/壁纸
  # 根因：nvidia-drm 没有 fbdev → Wayland compositor 无法初始化 KMS 输出
  boot.kernelParams = [ "nvidia-drm.fbdev=1" "nvidia-drm.modeset=1" "nvidia.NVreg_EnableGpuFirmware=0" "nvidia.NVreg_PreserveVideoMemoryAllocations=1" "nmi_watchdog=1" ];

  # Windows EFI 分区挂载（GRUB chainload 用）
  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };

  # ============================================================
  # NVIDIA 崩溃多重防护（第 3-5 层）
  # ============================================================

  # 第 3 层：内核硬件 watchdog — 内核本身卡死时强制硬重启
  # 原理：softdog 每 60s 喂一次，超时硬件复位，连 SysRq 都不响应也能救
  boot.kernelModules = [ "softdog" ];
  systemd.watchdog.runtimeTime = "60s";
  systemd.watchdog.rebootTime = "120s";
  systemd.watchdog.kexecTime = "30s";

  # 第 4 层：负载异常 watchdog — D 态进程堆积（load > 50）时 SysRq 重启
  systemd.services.nvidia-load-watchdog = {
    description = "NVIDIA D-state storm detector";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nvidia-load-watch" ''
        load=$(awk '{print int($1)}' /proc/loadavg)
        dstate=$(grep -l "State:.*D" /proc/[0-9]*/status 2>/dev/null | wc -l)
        if [ "$load" -gt 50 ] || [ "$dstate" -gt 20 ]; then
          echo "NVIDIA watchdog: load=$load dstate=$dstate, triggering reboot" | systemd-cat -p crit -t nvidia-watchdog
          echo 1 > /proc/sys/kernel/sysrq
          sync
          echo b > /proc/sysrq-trigger
        fi
      '';
    };
  };
  systemd.timers.nvidia-load-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "60s";
      AccuracySec = "10s";
    };
  };

  # 第 5 层：SysRq 永久开启 + panic 自动重启
  boot.kernel.sysctl."kernel.sysrq" = 1;
  boot.kernel.sysctl."kernel.panic" = 30;        # panic 后 30s 自动重启
  boot.kernel.sysctl."kernel.panic_on_oops" = 1; # oops 视为 panic

}
