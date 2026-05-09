{ config, pkgs, lib, ... }:

# ============================================================
# 磁盘池管理模块
# 原理：
#   底层 POOL 盘由 storage.nix 声明式挂载
#   本模块只负责 MergerFS 合并 + SnapRAID 校验
# ============================================================

{
  # MergerFS 合并 + SnapRAID 配置服务
  # 依赖 POOL-D1 和 POOL-E1 挂载就绪后运行
  systemd.services.disk-pool = {
    description = "MergerFS pool merge + SnapRAID config";
    after = [
      "local-fs.target"
      "mnt-pool\\x2ddisks-POOL\\x2dD1.mount"
      "mnt-pool\\x2ddisks-POOL\\x2dE1.mount"
    ];
    wants = [
      "mnt-pool\\x2ddisks-POOL\\x2dD1.mount"
      "mnt-pool\\x2ddisks-POOL\\x2dE1.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ util-linux coreutils ntfs3g mergerfs gawk gnugrep findutils mount ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "60";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh start";
      ExecStop = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh stop";
    };
  };

  # 定时检查新盘（热插拔检测）
  systemd.timers.disk-pool-scan = {
    description = "Check for new POOL disks every 5 min";
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
      TimeoutStartSec = "30";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/disk-pool-mount.sh rescan";
    };
  };

  # SnapRAID 每日校验
  systemd.services.snapraid-sync = {
    description = "SnapRAID sync parity data";
    after = [ "disk-pool.service" ];
    path = with pkgs; [ snapraid bash ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "300";
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
