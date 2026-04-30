{ config, pkgs, ... }: {
  # 自动挂载 sda4 (拷貝 3 大存儲 2)
  # 可拆卸 HDD 用 ntfs-3g（FUSE），避免 ntfs3 内核驱动脏卷卡死
  # NVMe 上的 win_c 保持 ntfs3（MFT 损坏 ntfs-3g 拒绝挂载）
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/C672D33272D32649";
    fsType = "ntfs-3g";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" "dmask=022" "fmask=133" ];
  };

  # Windows C: 盘 (只读挂载，供 KDE 搜索)
  # MFT 已用 ntfsfix 修复（2026-04-15），统一 ntfs-3g
  fileSystems."/mnt/win_c" = {
    device = "/dev/disk/by-uuid/0E8D03FB0E8D03FB";
    fsType = "ntfs-3g";
    options = [ "nofail" "ro" "uid=1000" "x-systemd.device-timeout=5s" ];
  };

  # Flatpak bind mount 到池分区（释放根分区 3.5G）
  fileSystems."/var/lib/flatpak" = {
 #    device = "/mnt/pool/offload/flatpak";
    fsType = "none";
    options = [ "bind" "nofail" ];
  };

  # AI 數據目录 — 原生 ext4 (POOL-D1, sdd1)，替代旧 loop image on NTFS
  # 迁移时间: 2026-04-22，性能提升: 去掉 loop+NTFS 两层开销
  fileSystems."/mnt/ai" = {
    device = "/mnt/pool-disks/POOL-D1/ai";
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires=mnt-pool\\x2ddisks-POOL\\x2dD1.mount" "x-systemd.after=mnt-pool\\x2ddisks-POOL\\x2dD1.mount" ];
  };

  # 方案 B: 将 /var 挂载到外置盘，减轻根分区压力
  # **已禁用** — NTFS 不支持 POSIX 权限/符号链接/文件锁，导致 systemd 服务失败
  # 症状：docker.service/syncthing.service/systemd-hostnamed.service 全部报 I/O 错误
  # 修复：/var 恢复到根分区（ext4），大数据目录单独 bind mount
  # fileSystems."/var" = {
  #   device = "/mnt/data/var";
  #   fsType = "none";
  #   options = [ "bind" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  # };

  # /tmp 使用 tmpfs（内存文件系统）— 修复 Claude Code Bash 工具 NTFS 权限问题
  # 原配置 bind mount 到 NTFS 导致权限错误，现改用 tmpfs
  # tmpfs 大小：50% 可用内存（24GB RAM → 最大 12GB）
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # === udisks2 配置 ===
  # 免认证 + 强制 NTFS 用 ntfs-3g（避免 ntfs3 内核驱动拒绝脏卷）
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

  # 旧配置（已禁用）：
  # fileSystems."/tmp" = {
  #   device = "/mnt/data/tmp";
  #   fsType = "none";
  #   options = [ "bind" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  # };
}
