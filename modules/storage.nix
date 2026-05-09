{ config, pkgs, ... }: {
  # ============================================================
  # 磁盘挂载统一声明（2026-05-09 重构）
  # 所有分区统一用 UUID 声明式挂载，udisks2 只做热插拔兜底
  # git clone → nixos-rebuild switch 即可恢复全部挂载点
  # ============================================================
  # 物理盘速查:
  #   nvme0n1  465G  Windows SSD    → 系统/应用/EFI
  #   sda      1.8T  POOL-B1       → 冷存储（外置）
  #   sdb      1.8T  POOL-A1 + 其他 → 主数据/游戏/备份
  #   sdc      1.8T  POOL-D1+PARITY → AI 数据 + 奇偶校验
  #   sdd      3.6T  POOL-E1       → 池扩展
  # 详见 /etc/nixos/DISK-LAYOUT.md
  # ============================================================

  # === NVMe 系统盘 (Windows 分区, 只读) ===
  fileSystems."/mnt/win_c" = {
    device = "/dev/disk/by-uuid/0E8D03FB0E8D03FB";
    fsType = "ntfs-3g";
    options = [ "nofail" "ro" "uid=1000" "x-systemd.device-timeout=5s" ];
  };
  fileSystems."/mnt/win_efi" = {
    device = "/dev/disk/by-uuid/FA67-631E";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };
  fileSystems."/mnt/SSD-WinExt" = {
    device = "/dev/disk/by-uuid/5E8C66368C6608BB";
    fsType = "ntfs-3g";
    options = [ "nofail" "ro" "uid=1000" "x-systemd.device-timeout=5s" ];
  };
  fileSystems."/mnt/SSD-WinApps" = {
    device = "/dev/disk/by-uuid/04F0C4BEF0C4B6E8";
    fsType = "ntfs-3g";
    options = [ "nofail" "ro" "uid=1000" "x-systemd.device-timeout=5s" ];
  };

  # === HDD 数据盘（可读写） ===
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/C672D33272D32649";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" "dmask=022" "fmask=133" ];
  };
  fileSystems."/mnt/HDD1-Games" = {
    device = "/dev/disk/by-uuid/1031167F1031167F";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" "dmask=022" "fmask=133" ];
  };
  fileSystems."/mnt/HDD1-Backup" = {
    device = "/dev/disk/by-uuid/0EF04734F0472177";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" "dmask=022" "fmask=133" ];
  };

  # === 池化存储底层（POOL 磁盘） ===
  fileSystems."/mnt/pool-disks/POOL-D1" = {
    device = "/dev/disk/by-uuid/d2c36cb2-ebe9-4317-a76c-c8eb239f2f32";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };
  fileSystems."/mnt/pool-disks/POOL-E1" = {
    device = "/dev/disk/by-uuid/DE22F5F022F5CD91";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=10s" "uid=1000" "dmask=022" "fmask=133" ];
  };
  fileSystems."/mnt/pool-disks/POOL-B1" = {
    device = "/dev/disk/by-uuid/B2BCF4DBBCF49B55";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=10s" "uid=1000" "dmask=022" "fmask=133" ];
  };

  # === AI 数据目录（bind mount 到 POOL-D1） ===
  fileSystems."/mnt/ai" = {
    device = "/mnt/pool-disks/POOL-D1/ai";
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires=mnt-pool\\x2ddisks-POOL\\x2dD1.mount" "x-systemd.after=mnt-pool\\x2ddisks-POOL\\x2dD1.mount" ];
  };

  # === mergerfs 池（POOL-D1 + POOL-E1 → /mnt/pool） ===
  # 由 disk-pool.sh 的 merge_pool() 动态合并
  # 底层 POOL 盘已由本文件声明式挂载，脚本只做 mergerfs 合并
  # 配置参考: /etc/nixos/scripts/disk-pool-mount.sh

  # /tmp 使用 tmpfs（内存文件系统）
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # === udisks2 配置（仅做热插拔兜底） ===
  # 固定挂载点已由本文件管理，udisks2 只负责未声明的热插拔盘
  services.udisks2.enable = true;
  services.udisks2.settings = {
    "mount_options.conf" = {
      defaults = {
        ntfs_drivers = "ntfs";
        ntfs_defaults = "uid=$UID,gid=$GID,windows_names";
        ntfs_allow = "uid=$UID,gid=$GID,umask,dmask,fmask,locale,norecover,ignore_case,windows_names";
      };
    };
  };
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
           action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
           action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat" ||
           action.id == "org.freedesktop.udisks2.filesystem-unmount-others" ||
           action.id == "org.freedesktop.udisks2.encrypted-unlock" ||
           action.id == "org.freedesktop.udisks2.eject-media" ||
           action.id == "org.freedesktop.udisks2.power-off-drive") &&
          subject.isInGroup("users")) {
        return polkit.Result.YES;
      }
    });
  '';
}
