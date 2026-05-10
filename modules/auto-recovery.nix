# 自动恢复系统启动和定时触发

{ config, pkgs, lib, ... }:

{
  # 启动时自动运行恢复检测
  systemd.services.auto-recovery = {
    description = "Automatic Data Recovery on Boot";
    after = [ "multi-user.target" "mnt-ai.mount" "mnt-pool.mount" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /home/charlie/.local/bin/recovery-manager auto";
      User = "charlie";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # 定时检测（每2小时）
  systemd.timers.periodic-recovery-check = {
    description = "Periodic Data Recovery Check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30min";
      OnUnitActiveSec = "2h";
      AccuracySec = "2min";
      Persistent = true;
    };
  };

  systemd.services.periodic-recovery-check = {
    description = "Periodic Recovery Check Service";
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /home/charlie/.local/bin/recovery-manager auto";
      User = "charlie";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
