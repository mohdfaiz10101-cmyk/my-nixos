{ config, pkgs, ... }: {
  # 自动挂载 sda4 (拷貝 3 大存儲 2)
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/C672D33272D32649";
    fsType = "ntfs3";
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" ];
  };

  # AI 數據 loopback 映像 (ext4 on NTFS)
  fileSystems."/mnt/ai" = {
    device = "/mnt/data/ai-data.img";
    fsType = "ext4";
    options = [ "loop" "nofail" "x-systemd.requires=mnt-data.mount" "x-systemd.after=mnt-data.mount" ];
  };
}
