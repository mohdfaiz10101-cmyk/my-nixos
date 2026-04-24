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
  system.activationScripts.syncGrubToEfi = lib.mkAfter ''
    if [ -f /boot/grub/grub.cfg ] && [ -d /boot/efi/grub ]; then
      cp /boot/grub/grub.cfg /boot/efi/grub/grub.cfg
    fi
  '';

  # Windows EFI 分区挂载（GRUB chainload 用）
  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };
}
