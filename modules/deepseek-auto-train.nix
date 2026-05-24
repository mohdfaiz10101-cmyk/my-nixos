{ config, pkgs, ... }:

# DeepSeek 自动训练 systemd timer
# 每周检查 Sonnet 案例，自动训练 LoRA adapter

{
  # 创建日志目录
  systemd.tmpfiles.rules = [
    "d /var/log 0755 root root -"
  ];

  # 自动训练 service
  systemd.services.deepseek-auto-train = {
    enable = false;
    description = "DeepSeek LoRA Auto Training";
    path = with pkgs; [ python3 bash coreutils docker ];
    serviceConfig = {
      Type = "oneshot";
      User = "charlie";
      ExecStart = "${pkgs.bash}/bin/bash /home/charlie/launcher/auto-train-deepseek.sh";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # 定时器：开机后每 7 天执行一次
  systemd.timers.deepseek-auto-train = {
    enable = false;
    description = "DeepSeek LoRA Auto Training Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";           # 开机 10 分钟后首次执行
      OnUnitActiveSec = "7d";        # 每次执行后 7 天再执行
      Persistent = true;             # 错过时间后启动时执行
      RandomizedDelaySec = "30m";    # 随机延迟避免负载尖峰
    };
  };
}
