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
    options = [ "bind" "nofail" ];
  };

  # AI 數據 loopback 映像 (ext4 on NTFS)
  fileSystems."/mnt/ai" = {
    device = "/mnt/data/ai-data.img";
    fsType = "ext4";
    options = [ "loop" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  };
}
