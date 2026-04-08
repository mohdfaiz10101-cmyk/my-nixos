{ config, pkgs, lib, ... }:

# ============================================================
# 磁盘自动池化模块
# 原理：开机扫描 POOL- 前缀分区 → 挂载 → MergerFS 合并
# 注：mergerfs, mergerfs-tools, snapraid, ntfs3g, e2fsprogs, parted
#     包已移至 modules/packages.nix
# ============================================================

{
  # 自动发现 + 挂载 + 合池 服务
  systemd.services.disk-pool = {
    description = "Auto-discover and pool POOL-* labeled disks";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ util-linux coreutils ntfs3g mergerfs gawk gnugrep findutils mount umount ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh start";
      ExecStop = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh stop";
    };
  };

  # 定时检查新盘（热插拔支持）
  systemd.timers.disk-pool-scan = {
    description = "Periodic scan for new POOL disks";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "5min";
    };
  };

  systemd.services.disk-pool-scan = {
    description = "Scan for new POOL disks";
    path = with pkgs; [ util-linux coreutils ntfs3g mergerfs gawk gnugrep findutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh rescan";
    };
  };

  # SnapRAID 每日校验（可选，如果有 PARITY 盘）
  systemd.services.snapraid-sync = {
    description = "SnapRAID sync parity data";
    path = with pkgs; [ snapraid bash ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'test -f /etc/snapraid.conf && snapraid sync || true'";
    };
  };

  systemd.timers.snapraid-sync = {
    description = "Daily SnapRAID sync (12:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 12:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
