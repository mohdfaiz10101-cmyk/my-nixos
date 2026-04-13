{ config, pkgs, ... }: {
  # 自动挂载 sda4 (拷貝 3 大存儲 2)
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/C672D33272D32649";
    fsType = "ntfs3";
    options = [ "nofail" "force" "x-systemd.device-timeout=5s" "uid=1000" ];
  };

  # Windows C: 盘 (只读挂载，供 KDE 搜索)
  fileSystems."/mnt/win_c" = {
    device = "/dev/disk/by-uuid/0E8D03FB0E8D03FB";
    fsType = "ntfs3";
    options = [ "nofail" "ro" "uid=1000" "iocharset=utf8" "x-systemd.device-timeout=5s" ];
  };

  # Flatpak bind mount 到池分区（释放根分区 3.5G）
  fileSystems."/var/lib/flatpak" = {
    device = "/mnt/pool/offload/flatpak";
    fsType = "none";
    options = [ "bind" "nofail" ];
  };

  # AI 數據 loopback 映像 (ext4 on NTFS) — 已禁用：镜像文件不存在
  # fileSystems."/mnt/ai" = {
  #   device = "/mnt/data/ai-data.img";
  #   fsType = "ext4";
  #   options = [ "loop" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  # };

  # 方案 B: 将 /var 挂载到外置盘，减轻根分区压力
  fileSystems."/var" = {
    device = "/mnt/data/var";
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  };

  # /tmp 使用 tmpfs（内存文件系统）— 修复 Claude Code Bash 工具 NTFS 权限问题
  # 原配置 bind mount 到 NTFS 导致权限错误，现改用 tmpfs
  # tmpfs 大小：50% 可用内存（24GB RAM → 最大 12GB）
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # 旧配置（已禁用）：
  # fileSystems."/tmp" = {
  #   device = "/mnt/data/tmp";
  #   fsType = "none";
  #   options = [ "bind" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  # };
}
